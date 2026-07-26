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
      return "이 앱은 macOS 14.2 이상이 필요합니다."
    case .noAudioProcess:
      return "선택한 앱의 오디오 프로세스를 찾지 못했습니다. 대상 앱에서 소리를 한 번 재생한 뒤 다시 시도해 주세요."
    case .invalidTap:
      return "선택한 앱의 시스템 오디오 캡처를 만들지 못했습니다."
    case .invalidAggregateDevice:
      return "캡처용 비공개 오디오 장치를 만들지 못했습니다."
    case .invalidAudioFormat:
      return "캡처된 오디오 형식을 재생할 수 없습니다."
    case .bufferAllocation:
      return "실시간 오디오 버퍼를 할당하지 못했습니다."
    case .processorAllocation:
      return "RVC 출력 처리기를 만들지 못했습니다."
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
          operation: "실시간 앱 오디오 캡처 시작",
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
