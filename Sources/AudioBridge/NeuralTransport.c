#include "AudioBridge.h"

#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

typedef struct CVSMonoRing {
  float *samples;
  uint32_t capacity;
  _Atomic uint_fast64_t readIndex;
  _Atomic uint_fast64_t writeIndex;
  _Atomic uint_fast64_t droppedFrames;
} CVSMonoRing;

struct CVSNeuralTransport {
  CVSMonoRing input;
  CVSMonoRing output;
  _Atomic int status;
  _Atomic uint32_t latencyFrames;
  _Atomic uint32_t inferenceMicroseconds;
  _Atomic uint32_t targetOutputFrames;
  _Atomic uint32_t maximumOutputFrames;
  _Atomic bool outputDiscardRequested;
  _Atomic bool streamResetRequested;
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

static bool initializeRing(CVSMonoRing *ring, uint32_t capacity) {
  ring->capacity = nextPowerOfTwo(capacity);
  ring->samples = calloc(ring->capacity, sizeof(float));
  if (ring->samples == NULL) {
    return false;
  }
  atomic_init(&ring->readIndex, 0);
  atomic_init(&ring->writeIndex, 0);
  atomic_init(&ring->droppedFrames, 0);
  return true;
}

static uint32_t ringAvailable(const CVSMonoRing *ring) {
  uint_fast64_t read =
      atomic_load_explicit(&ring->readIndex, memory_order_acquire);
  uint_fast64_t write =
      atomic_load_explicit(&ring->writeIndex, memory_order_acquire);
  uint_fast64_t available = write - read;
  return available > ring->capacity ? ring->capacity : (uint32_t)available;
}

static uint32_t ringWrite(CVSMonoRing *ring, const float *samples,
                          uint32_t frameCount) {
  if (ring == NULL || samples == NULL || frameCount == 0) {
    return 0;
  }
  uint_fast64_t write =
      atomic_load_explicit(&ring->writeIndex, memory_order_relaxed);
  uint_fast64_t read =
      atomic_load_explicit(&ring->readIndex, memory_order_acquire);
  uint_fast64_t used = write - read;
  uint32_t freeFrames =
      used >= ring->capacity ? 0 : ring->capacity - (uint32_t)used;
  uint32_t framesToWrite =
      frameCount < freeFrames ? frameCount : freeFrames;
  uint32_t mask = ring->capacity - 1;
  uint32_t start = (uint32_t)write & mask;
  uint32_t first =
      framesToWrite < ring->capacity - start ? framesToWrite
                                             : ring->capacity - start;
  if (first > 0) {
    memcpy(ring->samples + start, samples, first * sizeof(float));
  }
  uint32_t second = framesToWrite - first;
  if (second > 0) {
    memcpy(ring->samples, samples + first, second * sizeof(float));
  }
  if (framesToWrite > 0) {
    atomic_store_explicit(&ring->writeIndex, write + framesToWrite,
                          memory_order_release);
  }
  if (framesToWrite < frameCount) {
    atomic_fetch_add_explicit(&ring->droppedFrames,
                              frameCount - framesToWrite,
                              memory_order_relaxed);
  }
  return framesToWrite;
}

static uint32_t ringRead(CVSMonoRing *ring, float *samples,
                         uint32_t frameCount) {
  if (ring == NULL || samples == NULL || frameCount == 0) {
    return 0;
  }
  uint_fast64_t read =
      atomic_load_explicit(&ring->readIndex, memory_order_relaxed);
  uint_fast64_t write =
      atomic_load_explicit(&ring->writeIndex, memory_order_acquire);
  uint_fast64_t available = write - read;
  uint32_t framesToRead =
      available < frameCount ? (uint32_t)available : frameCount;
  uint32_t mask = ring->capacity - 1;
  uint32_t start = (uint32_t)read & mask;
  uint32_t first = framesToRead < ring->capacity - start
                       ? framesToRead
                       : ring->capacity - start;
  if (first > 0) {
    memcpy(samples, ring->samples + start, first * sizeof(float));
  }
  uint32_t second = framesToRead - first;
  if (second > 0) {
    memcpy(samples + first, ring->samples, second * sizeof(float));
  }
  if (framesToRead > 0) {
    atomic_store_explicit(&ring->readIndex, read + framesToRead,
                          memory_order_release);
  }
  return framesToRead;
}

static void resetRing(CVSMonoRing *ring) {
  atomic_store_explicit(&ring->readIndex, 0, memory_order_relaxed);
  atomic_store_explicit(&ring->writeIndex, 0, memory_order_relaxed);
  atomic_store_explicit(&ring->droppedFrames, 0, memory_order_relaxed);
  memset(ring->samples, 0, ring->capacity * sizeof(float));
}

CVSNeuralTransport *CVSNeuralTransportCreate(uint32_t capacityFrames) {
  CVSNeuralTransport *transport = calloc(1, sizeof(CVSNeuralTransport));
  if (transport == NULL) {
    return NULL;
  }
  if (!initializeRing(&transport->input, capacityFrames) ||
      !initializeRing(&transport->output, capacityFrames)) {
    free(transport->input.samples);
    free(transport->output.samples);
    free(transport);
    return NULL;
  }
  atomic_init(&transport->status, CVSNeuralStatusDisabled);
  atomic_init(&transport->latencyFrames, 0);
  atomic_init(&transport->inferenceMicroseconds, 0);
  atomic_init(&transport->targetOutputFrames, 0);
  atomic_init(&transport->maximumOutputFrames, 0);
  atomic_init(&transport->outputDiscardRequested, false);
  atomic_init(&transport->streamResetRequested, false);
  return transport;
}

void CVSNeuralTransportDestroy(CVSNeuralTransport *transport) {
  if (transport == NULL) {
    return;
  }
  free(transport->input.samples);
  free(transport->output.samples);
  free(transport);
}

uint32_t CVSNeuralTransportPushInput(CVSNeuralTransport *transport,
                                     const float *samples,
                                     uint32_t frameCount) {
  return transport == NULL ? 0
                           : ringWrite(&transport->input, samples, frameCount);
}

uint32_t CVSNeuralTransportPopInput(CVSNeuralTransport *transport,
                                    float *samples, uint32_t frameCount) {
  return transport == NULL ? 0
                           : ringRead(&transport->input, samples, frameCount);
}

uint32_t CVSNeuralTransportAvailableInput(CVSNeuralTransport *transport) {
  return transport == NULL ? 0 : ringAvailable(&transport->input);
}

void CVSNeuralTransportDiscardInput(CVSNeuralTransport *transport) {
  if (transport == NULL) {
    return;
  }
  uint_fast64_t write =
      atomic_load_explicit(&transport->input.writeIndex, memory_order_acquire);
  atomic_store_explicit(&transport->input.readIndex, write,
                        memory_order_release);
}

uint32_t CVSNeuralTransportPushOutput(CVSNeuralTransport *transport,
                                      const float *samples,
                                      uint32_t frameCount) {
  return transport == NULL ? 0
                           : ringWrite(&transport->output, samples, frameCount);
}

uint32_t CVSNeuralTransportPopOutput(CVSNeuralTransport *transport,
                                     float *samples, uint32_t frameCount) {
  return transport == NULL ? 0
                           : ringRead(&transport->output, samples, frameCount);
}

uint32_t CVSNeuralTransportAvailableOutput(CVSNeuralTransport *transport) {
  return transport == NULL ? 0 : ringAvailable(&transport->output);
}

void CVSNeuralTransportDiscardOutput(CVSNeuralTransport *transport) {
  if (transport == NULL) {
    return;
  }
  uint_fast64_t write =
      atomic_load_explicit(&transport->output.writeIndex, memory_order_acquire);
  atomic_store_explicit(&transport->output.readIndex, write,
                        memory_order_release);
}

void CVSNeuralTransportRequestOutputDiscard(
    CVSNeuralTransport *transport) {
  if (transport != NULL) {
    atomic_store_explicit(&transport->outputDiscardRequested, true,
                          memory_order_release);
  }
}

bool CVSNeuralTransportTakeOutputDiscardRequest(
    CVSNeuralTransport *transport) {
  return transport != NULL &&
         atomic_exchange_explicit(&transport->outputDiscardRequested, false,
                                  memory_order_acq_rel);
}

void CVSNeuralTransportRequestStreamReset(
    CVSNeuralTransport *transport) {
  if (transport != NULL) {
    atomic_store_explicit(&transport->streamResetRequested, true,
                          memory_order_release);
  }
}

bool CVSNeuralTransportTakeStreamResetRequest(
    CVSNeuralTransport *transport) {
  return transport != NULL &&
         atomic_exchange_explicit(&transport->streamResetRequested, false,
                                  memory_order_acq_rel);
}

void CVSNeuralTransportReset(CVSNeuralTransport *transport) {
  if (transport == NULL) {
    return;
  }
  resetRing(&transport->input);
  resetRing(&transport->output);
  atomic_store_explicit(&transport->latencyFrames, 0, memory_order_relaxed);
  atomic_store_explicit(&transport->inferenceMicroseconds, 0,
                        memory_order_relaxed);
  atomic_store_explicit(&transport->targetOutputFrames, 0,
                        memory_order_relaxed);
  atomic_store_explicit(&transport->maximumOutputFrames, 0,
                        memory_order_relaxed);
  atomic_store_explicit(&transport->outputDiscardRequested, false,
                        memory_order_relaxed);
  atomic_store_explicit(&transport->streamResetRequested, false,
                        memory_order_relaxed);
}

void CVSNeuralTransportSetStatus(CVSNeuralTransport *transport,
                                 CVSNeuralStatus status) {
  if (transport != NULL) {
    atomic_store_explicit(&transport->status, status, memory_order_release);
  }
}

CVSNeuralStatus CVSNeuralTransportGetStatus(CVSNeuralTransport *transport) {
  if (transport == NULL) {
    return CVSNeuralStatusDisabled;
  }
  return (CVSNeuralStatus)atomic_load_explicit(&transport->status,
                                               memory_order_acquire);
}

void CVSNeuralTransportSetMetrics(CVSNeuralTransport *transport,
                                  uint32_t latencyFrames,
                                  uint32_t inferenceMicroseconds) {
  if (transport == NULL) {
    return;
  }
  atomic_store_explicit(&transport->latencyFrames, latencyFrames,
                        memory_order_release);
  atomic_store_explicit(&transport->inferenceMicroseconds,
                        inferenceMicroseconds, memory_order_release);
}

void CVSNeuralTransportSetOutputBufferTargets(
    CVSNeuralTransport *transport, uint32_t targetFrames,
    uint32_t maximumFrames) {
  if (transport == NULL) {
    return;
  }
  uint32_t boundedTarget =
      targetFrames < maximumFrames ? targetFrames : maximumFrames;
  atomic_store_explicit(&transport->maximumOutputFrames, maximumFrames,
                        memory_order_release);
  atomic_store_explicit(&transport->targetOutputFrames, boundedTarget,
                        memory_order_release);
}

uint32_t
CVSNeuralTransportTargetOutputFrames(CVSNeuralTransport *transport) {
  return transport == NULL
             ? 0
             : atomic_load_explicit(&transport->targetOutputFrames,
                                    memory_order_acquire);
}

uint32_t
CVSNeuralTransportMaximumOutputFrames(CVSNeuralTransport *transport) {
  return transport == NULL
             ? 0
             : atomic_load_explicit(&transport->maximumOutputFrames,
                                    memory_order_acquire);
}

uint32_t CVSNeuralTransportLatencyFrames(CVSNeuralTransport *transport) {
  return transport == NULL
             ? 0
             : atomic_load_explicit(&transport->latencyFrames,
                                    memory_order_acquire);
}

uint32_t
CVSNeuralTransportInferenceMicroseconds(CVSNeuralTransport *transport) {
  return transport == NULL
             ? 0
             : atomic_load_explicit(&transport->inferenceMicroseconds,
                                    memory_order_acquire);
}

uint64_t
CVSNeuralTransportDroppedInputFrames(CVSNeuralTransport *transport) {
  return transport == NULL
             ? 0
             : atomic_load_explicit(&transport->input.droppedFrames,
                                    memory_order_relaxed);
}

uint64_t
CVSNeuralTransportDroppedOutputFrames(CVSNeuralTransport *transport) {
  return transport == NULL
             ? 0
             : atomic_load_explicit(&transport->output.droppedFrames,
                                    memory_order_relaxed);
}
