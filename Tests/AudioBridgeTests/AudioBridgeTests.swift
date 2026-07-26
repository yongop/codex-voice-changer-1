import AudioBridge
import AudioToolbox
@testable import CodexVoiceChanger1
import XCTest

final class AudioBridgeTests: XCTestCase {
  func testRoundTripStereoSamples() throws {
    let bridge = try XCTUnwrap(CVSAudioBridgeCreate(8))
    defer { CVSAudioBridgeDestroy(bridge) }

    let input: [Float] = [0.1, -0.1, 0.2, -0.2, 0.3, -0.3]
    XCTAssertEqual(
      input.withUnsafeBufferPointer {
        CVSAudioBridgeWriteTestStereo(bridge, $0.baseAddress!, 3)
      },
      3
    )

    var left = [Float](repeating: 0, count: 3)
    var right = [Float](repeating: 0, count: 3)
    renderBridge(bridge: bridge, left: &left, right: &right)
    XCTAssertEqual(left, [0.1, 0.2, 0.3])
    XCTAssertEqual(right, [-0.1, -0.2, -0.3])
    XCTAssertEqual(CVSAudioBridgeAvailableFrames(bridge), 0)
  }

  func testOversizedSingleWriteKeepsNewestCapacity() throws {
    let bridge = try XCTUnwrap(CVSAudioBridgeCreate(4))
    defer { CVSAudioBridgeDestroy(bridge) }

    let input: [Float] = [
      1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6,
    ]
    _ = input.withUnsafeBufferPointer {
      CVSAudioBridgeWriteTestStereo(bridge, $0.baseAddress!, 6)
    }
    XCTAssertEqual(CVSAudioBridgeAvailableFrames(bridge), 4)
  }

  func testPartialOverflowDoesNotOverwriteUnreadFrames() throws {
    let bridge = try XCTUnwrap(CVSAudioBridgeCreate(4))
    defer { CVSAudioBridgeDestroy(bridge) }

    let first: [Float] = [1, -1, 2, -2, 3, -3]
    let second: [Float] = [4, -4, 5, -5, 6, -6]
    XCTAssertEqual(
      first.withUnsafeBufferPointer {
        CVSAudioBridgeWriteTestStereo(bridge, $0.baseAddress!, 3)
      },
      3
    )
    XCTAssertEqual(
      second.withUnsafeBufferPointer {
        CVSAudioBridgeWriteTestStereo(bridge, $0.baseAddress!, 3)
      },
      1
    )

    var left = [Float](repeating: 0, count: 4)
    var right = [Float](repeating: 0, count: 4)
    XCTAssertEqual(
      left.withUnsafeMutableBufferPointer { leftPointer in
        right.withUnsafeMutableBufferPointer { rightPointer in
          CVSAudioBridgeReadPlanar(
            bridge,
            leftPointer.baseAddress!,
            rightPointer.baseAddress!,
            4
          )
        }
      },
      4
    )
    XCTAssertEqual(left, [1, 2, 3, 4])
    XCTAssertEqual(right, [-1, -2, -3, -4])
  }

  func testRVCTransportIsStrictSPSCAndTracksOverflow() throws {
    let transport = try XCTUnwrap(CVSNeuralTransportCreate(4))
    defer { CVSNeuralTransportDestroy(transport) }
    let input: [Float] = [1, 2, 3, 4, 5, 6]
    XCTAssertEqual(
      input.withUnsafeBufferPointer {
        CVSNeuralTransportPushInput(
          transport,
          $0.baseAddress!,
          UInt32($0.count)
        )
      },
      4
    )
    XCTAssertEqual(CVSNeuralTransportAvailableInput(transport), 4)
    XCTAssertEqual(CVSNeuralTransportDroppedInputFrames(transport), 2)

    var output = [Float](repeating: 0, count: 4)
    XCTAssertEqual(
      output.withUnsafeMutableBufferPointer {
        CVSNeuralTransportPopInput(
          transport,
          $0.baseAddress!,
          UInt32($0.count)
        )
      },
      4
    )
    XCTAssertEqual(output, [1, 2, 3, 4])
  }

  func testRVCUnderrunFallsBackToDryAudioAndRecovers() throws {
    let sampleRate = 48_000.0
    let quantum = 256
    let totalFrames = quantum * 24
    let bridge = try XCTUnwrap(
      CVSAudioBridgeCreate(UInt32(totalFrames * 2))
    )
    defer { CVSAudioBridgeDestroy(bridge) }
    let transport = try XCTUnwrap(
      CVSNeuralTransportCreate(UInt32(totalFrames * 2))
    )
    defer { CVSNeuralTransportDestroy(transport) }
    let processor = try XCTUnwrap(
      CVSRVCProcessorCreate(
        bridge,
        transport,
        sampleRate,
        UInt32(quantum)
      )
    )
    defer { CVSRVCProcessorDestroy(processor) }

    let source = [Float](repeating: 0.25, count: totalFrames * 2)
    XCTAssertEqual(
      source.withUnsafeBufferPointer {
        CVSAudioBridgeWriteTestStereo(
          bridge,
          $0.baseAddress!,
          UInt32(totalFrames)
        )
      },
      UInt32(totalFrames)
    )
    CVSNeuralTransportSetMetrics(transport, 512, 125_000)
    CVSNeuralTransportSetStatus(transport, CVSNeuralStatusWarmingUp)

    var fallbackLeft = [Float](repeating: 0, count: quantum)
    var fallbackRight = [Float](repeating: 0, count: quantum)
    for _ in 0..<3 {
      render(
        processor: processor,
        left: &fallbackLeft,
        right: &fallbackRight
      )
    }
    XCTAssertGreaterThan(fallbackLeft.min() ?? 0, 0.24)
    XCTAssertGreaterThan(fallbackRight.min() ?? 0, 0.24)

    let firstConverted = [Float](
      repeating: 0.8,
      count: quantum * 4
    )
    XCTAssertEqual(
      firstConverted.withUnsafeBufferPointer {
        CVSNeuralTransportPushOutput(
          transport,
          $0.baseAddress!,
          UInt32($0.count)
        )
      },
      UInt32(firstConverted.count)
    )
    CVSNeuralTransportSetStatus(transport, CVSNeuralStatusReady)
    for _ in 0..<4 {
      render(
        processor: processor,
        left: &fallbackLeft,
        right: &fallbackRight
      )
    }
    XCTAssertGreaterThan(fallbackLeft.last ?? 0, 0.65)

    // No converted block is available. The delayed source must replace it,
    // never silence, and a later converted block must still be accepted.
    for _ in 0..<5 {
      render(
        processor: processor,
        left: &fallbackLeft,
        right: &fallbackRight
      )
    }
    XCTAssertGreaterThan(fallbackLeft.min() ?? 0, 0.2)
    XCTAssertGreaterThan(fallbackRight.min() ?? 0, 0.2)

    let recovered = [Float](
      repeating: -0.6,
      count: quantum * 4
    )
    XCTAssertEqual(
      recovered.withUnsafeBufferPointer {
        CVSNeuralTransportPushOutput(
          transport,
          $0.baseAddress!,
          UInt32($0.count)
        )
      },
      UInt32(recovered.count)
    )
    for _ in 0..<4 {
      render(
        processor: processor,
        left: &fallbackLeft,
        right: &fallbackRight
      )
    }
    XCTAssertLessThan(fallbackLeft.last ?? 0, -0.4)
    XCTAssertFalse(CVSNeuralTransportTakeStreamResetRequest(transport))
  }

  func testSustainedRVCUnderrunRequestsFreshStreamWithoutSilence() throws {
    let sampleRate = 48_000.0
    let quantum = 512
    let totalFrames = quantum * 24
    let bridge = try XCTUnwrap(
      CVSAudioBridgeCreate(UInt32(totalFrames * 2))
    )
    defer { CVSAudioBridgeDestroy(bridge) }
    let transport = try XCTUnwrap(
      CVSNeuralTransportCreate(UInt32(totalFrames * 2))
    )
    defer { CVSNeuralTransportDestroy(transport) }
    let processor = try XCTUnwrap(
      CVSRVCProcessorCreate(
        bridge,
        transport,
        sampleRate,
        UInt32(quantum)
      )
    )
    defer { CVSRVCProcessorDestroy(processor) }

    let source = [Float](repeating: 0.2, count: totalFrames * 2)
    _ = source.withUnsafeBufferPointer {
      CVSAudioBridgeWriteTestStereo(
        bridge,
        $0.baseAddress!,
        UInt32(totalFrames)
      )
    }
    CVSNeuralTransportSetMetrics(transport, 512, 125_000)
    CVSNeuralTransportSetStatus(transport, CVSNeuralStatusReady)

    var left = [Float](repeating: 0, count: quantum)
    var right = [Float](repeating: 0, count: quantum)
    for _ in 0..<13 {
      render(processor: processor, left: &left, right: &right)
      if left.contains(where: { abs($0) > 0.001 }) {
        XCTAssertGreaterThan(left.max() ?? 0, 0.05)
      }
    }
    XCTAssertTrue(CVSNeuralTransportTakeStreamResetRequest(transport))
    XCTAssertGreaterThan(left.min() ?? 0, 0.15)

    // A reset can finish between two render callbacks. The discard
    // acknowledgement itself must unlock recovery even if no callback
    // observes the intermediate warming-up status.
    CVSNeuralTransportDiscardInput(transport)
    CVSNeuralTransportRequestOutputDiscard(transport)
    CVSNeuralTransportSetStatus(transport, CVSNeuralStatusReady)
    render(processor: processor, left: &left, right: &right)

    let recovered = [Float](repeating: -0.5, count: quantum * 4)
    _ = recovered.withUnsafeBufferPointer {
      CVSNeuralTransportPushOutput(
        transport,
        $0.baseAddress!,
        UInt32($0.count)
      )
    }
    for _ in 0..<4 {
      render(processor: processor, left: &left, right: &right)
    }
    XCTAssertLessThan(left.last ?? 0, -0.3)
  }

  private func renderBridge(
    bridge: OpaquePointer,
    left: inout [Float],
    right: inout [Float]
  ) {
    let frameCount = UInt32(left.count)
    withAudioBufferList(left: &left, right: &right) { list in
      XCTAssertEqual(
        CVSAudioBridgeRender(bridge, list, frameCount),
        noErr
      )
    }
  }

  private func render(
    processor: OpaquePointer,
    left: inout [Float],
    right: inout [Float]
  ) {
    let frameCount = UInt32(left.count)
    withAudioBufferList(left: &left, right: &right) { list in
      XCTAssertEqual(
        CVSRVCProcessorRender(processor, list, frameCount),
        noErr
      )
    }
  }

  private func withAudioBufferList(
    left: inout [Float],
    right: inout [Float],
    _ body: (UnsafeMutablePointer<AudioBufferList>) -> Void
  ) {
    let frameCount = left.count
    left.withUnsafeMutableBytes { leftBytes in
      right.withUnsafeMutableBytes { rightBytes in
        let size =
          MemoryLayout<AudioBufferList>.size
          + MemoryLayout<AudioBuffer>.size
        let pointer = UnsafeMutableRawPointer.allocate(
          byteCount: size,
          alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { pointer.deallocate() }
        let list = pointer.bindMemory(
          to: AudioBufferList.self,
          capacity: 1
        )
        list.pointee.mNumberBuffers = 2
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        buffers[0] = AudioBuffer(
          mNumberChannels: 1,
          mDataByteSize: UInt32(frameCount * MemoryLayout<Float>.size),
          mData: leftBytes.baseAddress
        )
        buffers[1] = AudioBuffer(
          mNumberChannels: 1,
          mDataByteSize: UInt32(frameCount * MemoryLayout<Float>.size),
          mData: rightBytes.baseAddress
        )
        body(list)
      }
    }
  }
}
