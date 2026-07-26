#include "AudioBridge.h"

#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

struct CVSAudioBridge {
  float *samples;
  uint32_t capacity;
  _Atomic uint_fast64_t readIndex;
  _Atomic uint_fast64_t writeIndex;
  AudioObjectID deviceID;
  AudioDeviceIOProcID ioProcID;
  bool isCapturing;
};

static uint32_t nextPowerOfTwo(uint32_t value) {
  if (value < 2) {
    return 2;
  }
  value--;
  value |= value >> 1;
  value |= value >> 2;
  value |= value >> 4;
  value |= value >> 8;
  value |= value >> 16;
  return value + 1;
}

static uint32_t writableFrames(CVSAudioBridge *bridge, uint_fast64_t write,
                               uint_fast64_t read, uint32_t requested) {
  uint_fast64_t used = write - read;
  uint32_t freeFrames =
      used >= bridge->capacity ? 0 : bridge->capacity - (uint32_t)used;
  return requested < freeFrames ? requested : freeFrames;
}

static uint32_t writeStereo(CVSAudioBridge *bridge, const float *interleaved,
                            uint32_t frameCount) {
  if (bridge == NULL || interleaved == NULL || frameCount == 0) {
    return 0;
  }

  uint_fast64_t write =
      atomic_load_explicit(&bridge->writeIndex, memory_order_relaxed);
  uint_fast64_t read =
      atomic_load_explicit(&bridge->readIndex, memory_order_acquire);

  if (frameCount > bridge->capacity) {
    interleaved += (frameCount - bridge->capacity) * 2;
    frameCount = bridge->capacity;
  }
  frameCount = writableFrames(bridge, write, read, frameCount);

  uint32_t mask = bridge->capacity - 1;
  for (uint32_t frame = 0; frame < frameCount; frame++) {
    uint32_t destination = (uint32_t)((write + frame) & mask) * 2;
    float left = interleaved[frame * 2];
    float right = interleaved[frame * 2 + 1];
    bridge->samples[destination] = left;
    bridge->samples[destination + 1] = right;
  }

  atomic_store_explicit(&bridge->writeIndex, write + frameCount,
                        memory_order_release);
  return frameCount;
}

static uint32_t writeAudioBufferList(CVSAudioBridge *bridge,
                                     const AudioBufferList *inputData) {
  if (bridge == NULL || inputData == NULL || inputData->mNumberBuffers == 0) {
    return 0;
  }

  const AudioBuffer *first = &inputData->mBuffers[0];
  if (first->mData == NULL || first->mDataByteSize == 0) {
    return 0;
  }

  // Process taps return Float32 linear PCM. A stereo mixdown is normally one
  // interleaved two-channel buffer, but handle planar and mono layouts too.
  if (inputData->mNumberBuffers == 1) {
    uint32_t channels = first->mNumberChannels;
    if (channels == 0) {
      return 0;
    }
    uint32_t frames = first->mDataByteSize / (sizeof(float) * channels);
    const float *source = (const float *)first->mData;

    if (channels == 2) {
      return writeStereo(bridge, source, frames);
    }

    uint_fast64_t write =
        atomic_load_explicit(&bridge->writeIndex, memory_order_relaxed);
    uint_fast64_t read =
        atomic_load_explicit(&bridge->readIndex, memory_order_acquire);
    if (frames > bridge->capacity) {
      source += (frames - bridge->capacity) * channels;
      frames = bridge->capacity;
    }
    frames = writableFrames(bridge, write, read, frames);

    uint32_t mask = bridge->capacity - 1;
    for (uint32_t frame = 0; frame < frames; frame++) {
      uint32_t destination = (uint32_t)((write + frame) & mask) * 2;
      float left = source[frame * channels];
      float right = channels > 1 ? source[frame * channels + 1] : left;
      bridge->samples[destination] = left;
      bridge->samples[destination + 1] = right;
    }
    atomic_store_explicit(&bridge->writeIndex, write + frames,
                          memory_order_release);
    return frames;
  }

  const AudioBuffer *leftBuffer = &inputData->mBuffers[0];
  const AudioBuffer *rightBuffer = &inputData->mBuffers[1];
  if (leftBuffer->mData == NULL || rightBuffer->mData == NULL) {
    return 0;
  }

  uint32_t leftFrames = leftBuffer->mDataByteSize / sizeof(float);
  uint32_t rightFrames = rightBuffer->mDataByteSize / sizeof(float);
  uint32_t frames = leftFrames < rightFrames ? leftFrames : rightFrames;
  const float *left = (const float *)leftBuffer->mData;
  const float *right = (const float *)rightBuffer->mData;

  uint_fast64_t write =
      atomic_load_explicit(&bridge->writeIndex, memory_order_relaxed);
  uint_fast64_t read =
      atomic_load_explicit(&bridge->readIndex, memory_order_acquire);
  if (frames > bridge->capacity) {
    uint32_t skip = frames - bridge->capacity;
    left += skip;
    right += skip;
    frames = bridge->capacity;
  }
  frames = writableFrames(bridge, write, read, frames);

  uint32_t mask = bridge->capacity - 1;
  for (uint32_t frame = 0; frame < frames; frame++) {
    uint32_t destination = (uint32_t)((write + frame) & mask) * 2;
    bridge->samples[destination] = left[frame];
    bridge->samples[destination + 1] = right[frame];
  }
  atomic_store_explicit(&bridge->writeIndex, write + frames,
                        memory_order_release);
  return frames;
}

static OSStatus
captureIOProc(AudioObjectID inDevice, const AudioTimeStamp *inNow,
              const AudioBufferList *inInputData,
              const AudioTimeStamp *inInputTime, AudioBufferList *outOutputData,
              const AudioTimeStamp *inOutputTime, void *inClientData) {
  (void)inDevice;
  (void)inNow;
  (void)inInputTime;
  (void)outOutputData;
  (void)inOutputTime;
  writeAudioBufferList((CVSAudioBridge *)inClientData, inInputData);
  return noErr;
}

CVSAudioBridge *CVSAudioBridgeCreate(uint32_t capacityFrames) {
  CVSAudioBridge *bridge = calloc(1, sizeof(CVSAudioBridge));
  if (bridge == NULL) {
    return NULL;
  }
  bridge->capacity = nextPowerOfTwo(capacityFrames);
  bridge->samples = calloc((size_t)bridge->capacity * 2, sizeof(float));
  if (bridge->samples == NULL) {
    free(bridge);
    return NULL;
  }
  atomic_init(&bridge->readIndex, 0);
  atomic_init(&bridge->writeIndex, 0);
  bridge->deviceID = kAudioObjectUnknown;
  bridge->ioProcID = NULL;
  bridge->isCapturing = false;
  return bridge;
}

void CVSAudioBridgeDestroy(CVSAudioBridge *bridge) {
  if (bridge == NULL) {
    return;
  }
  CVSAudioBridgeStopCapture(bridge);
  free(bridge->samples);
  free(bridge);
}

OSStatus CVSAudioBridgeStartCapture(CVSAudioBridge *bridge,
                                    AudioObjectID deviceID) {
  if (bridge == NULL || deviceID == kAudioObjectUnknown) {
    return kAudioHardwareBadObjectError;
  }
  if (bridge->isCapturing) {
    return noErr;
  }

  bridge->deviceID = deviceID;
  OSStatus status = AudioDeviceCreateIOProcID(deviceID, captureIOProc, bridge,
                                              &bridge->ioProcID);
  if (status != noErr) {
    bridge->ioProcID = NULL;
    bridge->deviceID = kAudioObjectUnknown;
    return status;
  }

  status = AudioDeviceStart(deviceID, bridge->ioProcID);
  if (status != noErr) {
    AudioDeviceDestroyIOProcID(deviceID, bridge->ioProcID);
    bridge->ioProcID = NULL;
    bridge->deviceID = kAudioObjectUnknown;
    return status;
  }
  bridge->isCapturing = true;
  return noErr;
}

void CVSAudioBridgeStopCapture(CVSAudioBridge *bridge) {
  if (bridge == NULL || bridge->ioProcID == NULL) {
    return;
  }
  AudioDeviceStop(bridge->deviceID, bridge->ioProcID);
  AudioDeviceDestroyIOProcID(bridge->deviceID, bridge->ioProcID);
  bridge->ioProcID = NULL;
  bridge->deviceID = kAudioObjectUnknown;
  bridge->isCapturing = false;
  atomic_store_explicit(&bridge->readIndex, 0, memory_order_relaxed);
  atomic_store_explicit(&bridge->writeIndex, 0, memory_order_relaxed);
}

uint32_t CVSAudioBridgeReadPlanar(CVSAudioBridge *bridge, float *left,
                                  float *right, uint32_t frameCount) {
  if (bridge == NULL || left == NULL || right == NULL) {
    return 0;
  }
  uint_fast64_t read =
      atomic_load_explicit(&bridge->readIndex, memory_order_relaxed);
  uint_fast64_t write =
      atomic_load_explicit(&bridge->writeIndex, memory_order_acquire);
  uint_fast64_t available = write - read;
  uint32_t framesToRead =
      available < frameCount ? (uint32_t)available : frameCount;
  uint32_t mask = bridge->capacity - 1;
  for (uint32_t frame = 0; frame < framesToRead; frame++) {
    uint32_t source = (uint32_t)((read + frame) & mask) * 2;
    left[frame] = bridge->samples[source];
    right[frame] = bridge->samples[source + 1];
  }
  if (framesToRead < frameCount) {
    memset(left + framesToRead, 0, (frameCount - framesToRead) * sizeof(float));
    memset(right + framesToRead, 0,
           (frameCount - framesToRead) * sizeof(float));
  }
  atomic_store_explicit(&bridge->readIndex, read + framesToRead,
                        memory_order_release);
  return framesToRead;
}

OSStatus CVSAudioBridgeRender(CVSAudioBridge *bridge,
                              AudioBufferList *outputData,
                              uint32_t frameCount) {
  if (bridge == NULL || outputData == NULL) {
    return kAudio_ParamError;
  }

  if (outputData->mNumberBuffers >= 2) {
    float *left = (float *)outputData->mBuffers[0].mData;
    float *right = (float *)outputData->mBuffers[1].mData;
    if (left == NULL || right == NULL) {
      return kAudio_ParamError;
    }
    CVSAudioBridgeReadPlanar(bridge, left, right, frameCount);
    outputData->mBuffers[0].mDataByteSize = frameCount * sizeof(float);
    outputData->mBuffers[1].mDataByteSize = frameCount * sizeof(float);
  } else if (outputData->mNumberBuffers == 1) {
    uint_fast64_t read =
        atomic_load_explicit(&bridge->readIndex, memory_order_relaxed);
    uint_fast64_t write =
        atomic_load_explicit(&bridge->writeIndex, memory_order_acquire);
    uint_fast64_t available = write - read;
    uint32_t framesToRead =
        available < frameCount ? (uint32_t)available : frameCount;
    uint32_t mask = bridge->capacity - 1;
    AudioBuffer *buffer = &outputData->mBuffers[0];
    float *samples = (float *)buffer->mData;
    if (samples == NULL) {
      return kAudio_ParamError;
    }
    uint32_t channels = buffer->mNumberChannels;
    if (channels == 0) {
      channels = 2;
    }
    for (uint32_t frame = 0; frame < framesToRead; frame++) {
      uint32_t source = (uint32_t)((read + frame) & mask) * 2;
      samples[frame * channels] = bridge->samples[source];
      if (channels > 1) {
        samples[frame * channels + 1] = bridge->samples[source + 1];
      }
      for (uint32_t channel = 2; channel < channels; channel++) {
        samples[frame * channels + channel] = 0.0f;
      }
    }
    if (framesToRead < frameCount) {
      memset(samples + framesToRead * channels, 0,
             (frameCount - framesToRead) * channels * sizeof(float));
    }
    buffer->mDataByteSize = frameCount * channels * sizeof(float);
    atomic_store_explicit(&bridge->readIndex, read + framesToRead,
                          memory_order_release);
  }
  return noErr;
}

uint32_t CVSAudioBridgeAvailableFrames(CVSAudioBridge *bridge) {
  if (bridge == NULL) {
    return 0;
  }
  uint_fast64_t read =
      atomic_load_explicit(&bridge->readIndex, memory_order_acquire);
  uint_fast64_t write =
      atomic_load_explicit(&bridge->writeIndex, memory_order_acquire);
  uint_fast64_t available = write - read;
  return available > UINT32_MAX ? UINT32_MAX : (uint32_t)available;
}

uint32_t CVSAudioBridgeWriteTestStereo(CVSAudioBridge *bridge,
                                       const float *interleavedStereo,
                                       uint32_t frameCount) {
  return writeStereo(bridge, interleavedStereo, frameCount);
}
