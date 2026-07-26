#ifndef CODEX_VOICE_CHANGER_1_AUDIO_BRIDGE_H
#define CODEX_VOICE_CHANGER_1_AUDIO_BRIDGE_H

#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct CVSAudioBridge CVSAudioBridge;
typedef struct CVSNeuralTransport CVSNeuralTransport;
typedef struct CVSRVCProcessor CVSRVCProcessor;

typedef enum CVSNeuralStatus {
  CVSNeuralStatusDisabled = 0,
  CVSNeuralStatusLoading = 1,
  CVSNeuralStatusWarmingUp = 2,
  CVSNeuralStatusReady = 3,
  CVSNeuralStatusFailed = 4,
} CVSNeuralStatus;

/// Stereo SPSC bridge between the Core Audio tap and the output renderer.
CVSAudioBridge *_Nullable CVSAudioBridgeCreate(uint32_t capacityFrames);
void CVSAudioBridgeDestroy(CVSAudioBridge *_Nullable bridge);
OSStatus CVSAudioBridgeStartCapture(CVSAudioBridge *_Nonnull bridge,
                                    AudioObjectID deviceID);
void CVSAudioBridgeStopCapture(CVSAudioBridge *_Nullable bridge);
OSStatus CVSAudioBridgeRender(CVSAudioBridge *_Nonnull bridge,
                              AudioBufferList *_Nonnull outputData,
                              uint32_t frameCount);
uint32_t CVSAudioBridgeAvailableFrames(CVSAudioBridge *_Nonnull bridge);
uint32_t CVSAudioBridgeReadPlanar(CVSAudioBridge *_Nonnull bridge,
                                  float *_Nonnull left, float *_Nonnull right,
                                  uint32_t frameCount);
uint32_t CVSAudioBridgeWriteTestStereo(CVSAudioBridge *_Nonnull bridge,
                                       const float *_Nonnull interleavedStereo,
                                       uint32_t frameCount);

/// Mono SPSC input/output rings connecting the real-time renderer and RVC
/// worker. The renderer produces input and consumes converted output.
CVSNeuralTransport *_Nullable CVSNeuralTransportCreate(
    uint32_t capacityFrames);
void CVSNeuralTransportDestroy(CVSNeuralTransport *_Nullable transport);
uint32_t CVSNeuralTransportPushInput(
    CVSNeuralTransport *_Nonnull transport, const float *_Nonnull samples,
    uint32_t frameCount);
uint32_t CVSNeuralTransportPopInput(CVSNeuralTransport *_Nonnull transport,
                                    float *_Nonnull samples,
                                    uint32_t frameCount);
uint32_t CVSNeuralTransportAvailableInput(
    CVSNeuralTransport *_Nonnull transport);
void CVSNeuralTransportDiscardInput(CVSNeuralTransport *_Nonnull transport);
uint32_t CVSNeuralTransportPushOutput(
    CVSNeuralTransport *_Nonnull transport, const float *_Nonnull samples,
    uint32_t frameCount);
uint32_t CVSNeuralTransportPopOutput(CVSNeuralTransport *_Nonnull transport,
                                     float *_Nonnull samples,
                                     uint32_t frameCount);
uint32_t CVSNeuralTransportAvailableOutput(
    CVSNeuralTransport *_Nonnull transport);
void CVSNeuralTransportDiscardOutput(CVSNeuralTransport *_Nonnull transport);
void CVSNeuralTransportRequestOutputDiscard(
    CVSNeuralTransport *_Nonnull transport);
bool CVSNeuralTransportTakeOutputDiscardRequest(
    CVSNeuralTransport *_Nonnull transport);
void CVSNeuralTransportRequestStreamReset(
    CVSNeuralTransport *_Nonnull transport);
bool CVSNeuralTransportTakeStreamResetRequest(
    CVSNeuralTransport *_Nonnull transport);
void CVSNeuralTransportReset(CVSNeuralTransport *_Nonnull transport);
void CVSNeuralTransportSetStatus(CVSNeuralTransport *_Nonnull transport,
                                 CVSNeuralStatus status);
CVSNeuralStatus CVSNeuralTransportGetStatus(
    CVSNeuralTransport *_Nonnull transport);
void CVSNeuralTransportSetMetrics(CVSNeuralTransport *_Nonnull transport,
                                  uint32_t latencyFrames,
                                  uint32_t inferenceMicroseconds);
void CVSNeuralTransportSetOutputBufferTargets(
    CVSNeuralTransport *_Nonnull transport, uint32_t targetFrames,
    uint32_t maximumFrames);
uint32_t CVSNeuralTransportTargetOutputFrames(
    CVSNeuralTransport *_Nonnull transport);
uint32_t CVSNeuralTransportMaximumOutputFrames(
    CVSNeuralTransport *_Nonnull transport);
uint32_t CVSNeuralTransportLatencyFrames(
    CVSNeuralTransport *_Nonnull transport);
uint32_t CVSNeuralTransportInferenceMicroseconds(
    CVSNeuralTransport *_Nonnull transport);
uint64_t CVSNeuralTransportDroppedInputFrames(
    CVSNeuralTransport *_Nonnull transport);
uint64_t CVSNeuralTransportDroppedOutputFrames(
    CVSNeuralTransport *_Nonnull transport);

/// RVC-only renderer. It always publishes mono input to the worker. Converted
/// output is preferred; a presentation-aligned dry signal crossfades in while
/// the model loads, fails, resets, or briefly misses a deadline.
CVSRVCProcessor *_Nullable CVSRVCProcessorCreate(
    CVSAudioBridge *_Nonnull bridge,
    CVSNeuralTransport *_Nonnull transport,
    double sampleRate,
    uint32_t maxFrames);
void CVSRVCProcessorDestroy(CVSRVCProcessor *_Nullable processor);
OSStatus CVSRVCProcessorRender(CVSRVCProcessor *_Nonnull processor,
                               AudioBufferList *_Nonnull outputData,
                               uint32_t frameCount);
uint32_t CVSRVCProcessorLatencyFrames(CVSRVCProcessor *_Nonnull processor);

#ifdef __cplusplus
}
#endif

#endif
