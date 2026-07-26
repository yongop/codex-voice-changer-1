#include "AudioBridge.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <vector>

namespace {

uint32_t nextPowerOfTwo(uint32_t value) {
  uint32_t result = 2;
  while (result < value && result < (1u << 30)) {
    result <<= 1;
  }
  return result;
}

} // namespace

struct CVSRVCProcessor {
  CVSAudioBridge *bridge;
  CVSNeuralTransport *transport;
  float sampleRate;
  uint32_t maxFrames;
  std::vector<float> inputLeft;
  std::vector<float> inputRight;
  std::vector<float> outputLeft;
  std::vector<float> outputRight;
  std::vector<float> rvcInput;
  std::vector<float> rvcOutput;
  std::vector<float> dryDelayLeft;
  std::vector<float> dryDelayRight;
  uint32_t dryDelayMask;
  uint_fast64_t dryWriteIndex = 0;
  uint_fast64_t underrunFrames = 0;
  float convertedMix = 0;
  float lastConvertedSample = 0;
  bool recoveryRequested = false;

  CVSRVCProcessor(CVSAudioBridge *audioBridge,
                  CVSNeuralTransport *rvcTransport, double rate,
                  uint32_t maximumFrames)
      : bridge(audioBridge), transport(rvcTransport),
        sampleRate(static_cast<float>(rate)),
        maxFrames(std::max<uint32_t>(maximumFrames, 512)),
        inputLeft(maxFrames, 0), inputRight(maxFrames, 0),
        outputLeft(maxFrames, 0), outputRight(maxFrames, 0),
        rvcInput(maxFrames, 0), rvcOutput(maxFrames, 0),
        dryDelayLeft(nextPowerOfTwo(static_cast<uint32_t>(rate * 1.25) +
                                    maxFrames),
                     0),
        dryDelayRight(dryDelayLeft.size(), 0),
        dryDelayMask(static_cast<uint32_t>(dryDelayLeft.size() - 1)) {}

  void renderDelayedDry(uint32_t frameCount) {
    uint32_t latencyFrames = CVSNeuralTransportLatencyFrames(transport);
    if (latencyFrames == 0) {
      latencyFrames =
          static_cast<uint32_t>(std::ceil(sampleRate * 0.42f));
    }
    latencyFrames =
        std::min(latencyFrames,
                 static_cast<uint32_t>(dryDelayLeft.size() - maxFrames - 1));

    for (uint32_t frame = 0; frame < frameCount; frame++) {
      uint32_t writeSlot = static_cast<uint32_t>(dryWriteIndex) & dryDelayMask;
      if (dryWriteIndex >= latencyFrames) {
        uint32_t readSlot =
            static_cast<uint32_t>(dryWriteIndex - latencyFrames) & dryDelayMask;
        outputLeft[frame] = dryDelayLeft[readSlot];
        outputRight[frame] = dryDelayRight[readSlot];
      } else {
        outputLeft[frame] = 0;
        outputRight[frame] = 0;
      }
      dryDelayLeft[writeSlot] = inputLeft[frame];
      dryDelayRight[writeSlot] = inputRight[frame];
      dryWriteIndex++;
    }
  }

  void mixConverted(uint32_t frameCount) {
    constexpr float kFadeInSeconds = 0.012f;
    float coefficient =
        1.0f - std::exp(-1.0f / (sampleRate * kFadeInSeconds));
    for (uint32_t frame = 0; frame < frameCount; frame++) {
      convertedMix += (1.0f - convertedMix) * coefficient;
      outputLeft[frame] +=
          (rvcOutput[frame] - outputLeft[frame]) * convertedMix;
      outputRight[frame] +=
          (rvcOutput[frame] - outputRight[frame]) * convertedMix;
    }
    lastConvertedSample = rvcOutput[frameCount - 1];
  }

  void mixFallback(uint32_t frameCount) {
    constexpr float kFadeOutSeconds = 0.008f;
    float coefficient =
        1.0f - std::exp(-1.0f / (sampleRate * kFadeOutSeconds));
    for (uint32_t frame = 0; frame < frameCount; frame++) {
      convertedMix += (0.0f - convertedMix) * coefficient;
      outputLeft[frame] +=
          (lastConvertedSample - outputLeft[frame]) * convertedMix;
      outputRight[frame] +=
          (lastConvertedSample - outputRight[frame]) * convertedMix;
    }
  }

  OSStatus render(AudioBufferList *outputData, uint32_t frameCount) {
    if (outputData == nullptr || frameCount > maxFrames) {
      return kAudio_ParamError;
    }

    CVSAudioBridgeReadPlanar(bridge, inputLeft.data(), inputRight.data(),
                             frameCount);
    for (uint32_t frame = 0; frame < frameCount; frame++) {
      rvcInput[frame] = (inputLeft[frame] + inputRight[frame]) * 0.5f;
    }

    CVSNeuralStatus status = CVSNeuralTransportGetStatus(transport);
    uint32_t pushed =
        CVSNeuralTransportPushInput(transport, rvcInput.data(), frameCount);
    if (pushed != frameCount && status == CVSNeuralStatusReady &&
        !recoveryRequested) {
      CVSNeuralTransportRequestStreamReset(transport);
      recoveryRequested = true;
    }

    renderDelayedDry(frameCount);
    if (CVSNeuralTransportTakeOutputDiscardRequest(transport)) {
      CVSNeuralTransportDiscardOutput(transport);
      underrunFrames = 0;
      convertedMix = 0;
      lastConvertedSample = 0;
      // The worker publishes this request only after acknowledging a reset
      // and moving its input read head to the live edge.
      recoveryRequested = false;
    }

    status = CVSNeuralTransportGetStatus(transport);
    bool convertedReady =
        status == CVSNeuralStatusReady && !recoveryRequested &&
        CVSNeuralTransportAvailableOutput(transport) >= frameCount;
    if (convertedReady) {
      convertedReady =
          CVSNeuralTransportPopOutput(transport, rvcOutput.data(), frameCount) ==
          frameCount;
    }

    if (convertedReady) {
      underrunFrames = 0;
      recoveryRequested = false;
      mixConverted(frameCount);
    } else {
      mixFallback(frameCount);
      if (status == CVSNeuralStatusReady && !recoveryRequested) {
        underrunFrames += frameCount;
        if (underrunFrames >=
            static_cast<uint_fast64_t>(sampleRate * 0.12f)) {
          CVSNeuralTransportRequestStreamReset(transport);
          recoveryRequested = true;
          underrunFrames = 0;
        }
      } else if (status != CVSNeuralStatusReady) {
        underrunFrames = 0;
      }
    }

    if (outputData->mNumberBuffers >= 2) {
      float *left = static_cast<float *>(outputData->mBuffers[0].mData);
      float *right = static_cast<float *>(outputData->mBuffers[1].mData);
      if (left == nullptr || right == nullptr) {
        return kAudio_ParamError;
      }
      std::memcpy(left, outputLeft.data(), frameCount * sizeof(float));
      std::memcpy(right, outputRight.data(), frameCount * sizeof(float));
      outputData->mBuffers[0].mDataByteSize = frameCount * sizeof(float);
      outputData->mBuffers[1].mDataByteSize = frameCount * sizeof(float);
      for (uint32_t buffer = 2; buffer < outputData->mNumberBuffers; buffer++) {
        if (outputData->mBuffers[buffer].mData != nullptr) {
          std::memset(outputData->mBuffers[buffer].mData, 0,
                      outputData->mBuffers[buffer].mDataByteSize);
        }
      }
    } else if (outputData->mNumberBuffers == 1) {
      AudioBuffer &buffer = outputData->mBuffers[0];
      float *samples = static_cast<float *>(buffer.mData);
      if (samples == nullptr) {
        return kAudio_ParamError;
      }
      uint32_t channels = std::max<uint32_t>(buffer.mNumberChannels, 1);
      for (uint32_t frame = 0; frame < frameCount; frame++) {
        samples[frame * channels] = outputLeft[frame];
        if (channels > 1) {
          samples[frame * channels + 1] = outputRight[frame];
        }
        for (uint32_t channel = 2; channel < channels; channel++) {
          samples[frame * channels + channel] = 0;
        }
      }
      buffer.mDataByteSize = frameCount * channels * sizeof(float);
    }
    return noErr;
  }
};

CVSRVCProcessor *CVSRVCProcessorCreate(CVSAudioBridge *bridge,
                                       CVSNeuralTransport *transport,
                                       double sampleRate, uint32_t maxFrames) {
  if (bridge == nullptr || transport == nullptr || sampleRate <= 0 ||
      maxFrames == 0) {
    return nullptr;
  }
  try {
    return new CVSRVCProcessor(bridge, transport, sampleRate, maxFrames);
  } catch (...) {
    return nullptr;
  }
}

void CVSRVCProcessorDestroy(CVSRVCProcessor *processor) { delete processor; }

OSStatus CVSRVCProcessorRender(CVSRVCProcessor *processor,
                               AudioBufferList *outputData,
                               uint32_t frameCount) {
  return processor == nullptr
             ? kAudio_ParamError
             : processor->render(outputData, frameCount);
}

uint32_t CVSRVCProcessorLatencyFrames(CVSRVCProcessor *processor) {
  return processor == nullptr
             ? 0
             : CVSNeuralTransportLatencyFrames(processor->transport);
}
