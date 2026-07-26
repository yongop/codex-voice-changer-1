import AVFAudio
import AudioBridge
import Foundation

@available(macOS 14.2, *)
final class RVCPlaybackEngine {
  private let engine = AVAudioEngine()
  private let sourceNode: AVAudioSourceNode
  private let sourceFormat: AVAudioFormat
  private let processor: OpaquePointer
  private let transport: OpaquePointer
  private let worker: RVCStreamingEngine
  private var isStarted = false

  init(
    bridge: OpaquePointer,
    sampleRate: Double,
    onActivityChange: @escaping @Sendable (RVCActivityState) -> Void
  ) throws {
    guard
      let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 2,
        interleaved: false
      )
    else {
      throw VoiceChangerError.invalidAudioFormat
    }
    guard
      let createdTransport = CVSNeuralTransportCreate(
        UInt32(min(max(sampleRate * 1.25, 32_768), 262_144))
      )
    else {
      throw VoiceChangerError.bufferAllocation
    }
    guard
      let createdProcessor = CVSRVCProcessorCreate(
        bridge,
        createdTransport,
        sampleRate,
        8_192
      )
    else {
      CVSNeuralTransportDestroy(createdTransport)
      throw VoiceChangerError.processorAllocation
    }

    sourceFormat = format
    transport = createdTransport
    processor = createdProcessor
    worker = RVCStreamingEngine(
      transport: createdTransport,
      sampleRate: sampleRate,
      onActivityChange: onActivityChange
    )
    sourceNode = AVAudioSourceNode { _, _, frameCount, audioBufferList in
      CVSRVCProcessorRender(
        createdProcessor,
        audioBufferList,
        frameCount
      )
    }

    engine.attach(sourceNode)
    engine.connect(
      sourceNode,
      to: engine.mainMixerNode,
      format: sourceFormat
    )
  }

  deinit {
    stop()
    CVSRVCProcessorDestroy(processor)
    CVSNeuralTransportDestroy(transport)
  }

  func start() throws {
    guard !isStarted else { return }
    engine.prepare()
    try engine.start()
    isStarted = true
    worker.start()
  }

  func stop() {
    guard isStarted else { return }
    isStarted = false
    engine.stop()
    worker.stop()
  }
}
