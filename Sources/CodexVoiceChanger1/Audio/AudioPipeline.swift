import AudioBridge
import CoreAudio
import Foundation

enum VoiceChangerError: LocalizedError {
  case unsupportedSystem
  case noAudioProcess
  case invalidTap
  case invalidAggregateDevice
  case invalidAudioFormat
  case bufferAllocation
  case processorAllocation

  var errorDescription: String? {
    switch self {
    case .unsupportedSystem:
      return L.s.errorUnsupportedSystem
    case .noAudioProcess:
      return L.s.errorNoAudioProcess
    case .invalidTap:
      return L.s.errorInvalidTap
    case .invalidAggregateDevice:
      return L.s.errorInvalidAggregateDevice
    case .invalidAudioFormat:
      return L.s.errorInvalidAudioFormat
    case .bufferAllocation:
      return L.s.errorBufferAllocation
    case .processorAllocation:
      return L.s.errorProcessorAllocation
    }
  }
}

@available(macOS 14.2, *)
final class AudioPipeline {
  private var bridge: OpaquePointer?
  private var tapSession: ProcessTapSession?
  private var playbackEngine: RVCPlaybackEngine?

  deinit {
    stop()
  }

  func start(
    pid: pid_t,
    bundleID: String,
    onActivityChange: @escaping @Sendable (RVCActivityState) -> Void
  ) throws {
    stop()

    // The tapped source is always muted. The renderer owns both the converted
    // path and the presentation-aligned dry fallback, so a worker failure can
    // never leave the selected app silent.
    let session = try ProcessTapSession(
      pid: pid,
      bundleID: bundleID,
      muteOriginal: true
    )
    let rate = session.format.mSampleRate
    let capacity = UInt32(min(max(rate * 0.5, 16_384), 65_536))
    guard let audioBridge = CVSAudioBridgeCreate(capacity) else {
      session.stop()
      throw VoiceChangerError.bufferAllocation
    }

    do {
      let playback = try RVCPlaybackEngine(
        bridge: audioBridge,
        sampleRate: rate,
        onActivityChange: onActivityChange
      )
      try playback.start()

      let captureStatus = CVSAudioBridgeStartCapture(
        audioBridge,
        session.aggregateDeviceID
      )
      guard captureStatus == noErr else {
        playback.stop()
        throw CoreAudioFailure(
          operation: .startCapture,
          status: captureStatus
        )
      }

      bridge = audioBridge
      tapSession = session
      playbackEngine = playback
    } catch {
      CVSAudioBridgeDestroy(audioBridge)
      session.stop()
      throw error
    }
  }

  func stop() {
    guard bridge != nil || tapSession != nil || playbackEngine != nil else {
      return
    }

    playbackEngine?.stop()
    playbackEngine = nil
    if let bridge {
      CVSAudioBridgeStopCapture(bridge)
      CVSAudioBridgeDestroy(bridge)
    }
    tapSession?.stop()

    bridge = nil
    tapSession = nil
  }
}
