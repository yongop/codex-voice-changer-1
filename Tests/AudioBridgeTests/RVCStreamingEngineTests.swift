import AudioBridge
@testable import CodexVoiceChanger1
import XCTest

private final class RVCActivityRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [RVCActivityState] = []

  func record(_ value: RVCActivityState) {
    lock.lock()
    values.append(value)
    lock.unlock()
  }

  func contains(_ value: RVCActivityState) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return values.contains(value)
  }
}

final class RVCStreamingEngineTests: XCTestCase {
  func testRealtimeConfigurationUsesMeasuredStableMargin() {
    XCTAssertEqual(RVCStreamingEngine.pitchShiftSemitones, 5)
    XCTAssertEqual(RVCStreamingEngine.blockSeconds, 0.22)
    XCTAssertEqual(RVCStreamingEngine.crossfadeSeconds, 0.05)
    XCTAssertEqual(RVCStreamingEngine.extraContextSeconds, 2.5)
    XCTAssertEqual(RVCStreamingEngine.schedulingReserveSeconds, 0.06)
  }

  func testWorkerIntegrationWhenRequested() throws {
    guard ProcessInfo.processInfo.environment[
      "CVS_RUN_RVC_INTEGRATION_TEST"
    ] == "1" else {
      throw XCTSkip(
        "Set CVS_RUN_RVC_INTEGRATION_TEST=1 for the MPS worker test."
      )
    }

    let transport = try XCTUnwrap(CVSNeuralTransportCreate(65_536))
    defer { CVSNeuralTransportDestroy(transport) }
    let activityRecorder = RVCActivityRecorder()
    let engine = RVCStreamingEngine(
      transport: transport,
      sampleRate: 48_000,
      onActivityChange: activityRecorder.record
    )
    engine.start()
    defer { engine.stop() }

    let warmupDeadline = Date().addingTimeInterval(35)
    while CVSNeuralTransportGetStatus(transport)
      == CVSNeuralStatusLoading,
      Date() < warmupDeadline
    {
      Thread.sleep(forTimeInterval: 0.02)
    }
    XCTAssertEqual(
      CVSNeuralTransportGetStatus(transport),
      CVSNeuralStatusWarmingUp
    )
    if CVSNeuralTransportTakeOutputDiscardRequest(transport) {
      CVSNeuralTransportDiscardOutput(transport)
    }

    let blockFrames = 10_560
    var input = [Float](repeating: 0, count: blockFrames)
    for frame in input.indices {
      input[frame] = Float(
        sin(2 * Double.pi * 162 * Double(frame) / 48_000) * 0.08
      )
    }
    XCTAssertEqual(
      input.withUnsafeBufferPointer {
        CVSNeuralTransportPushInput(
          transport,
          $0.baseAddress!,
          UInt32($0.count)
        )
      },
      UInt32(blockFrames)
    )

    let outputDeadline = Date().addingTimeInterval(3)
    while CVSNeuralTransportGetStatus(transport)
      != CVSNeuralStatusReady,
      Date() < outputDeadline
    {
      if CVSNeuralTransportTakeOutputDiscardRequest(transport) {
        CVSNeuralTransportDiscardOutput(transport)
      }
      Thread.sleep(forTimeInterval: 0.005)
    }
    XCTAssertEqual(
      CVSNeuralTransportGetStatus(transport),
      CVSNeuralStatusReady
    )
    XCTAssertTrue(activityRecorder.contains(.preparing))
    XCTAssertTrue(activityRecorder.contains(.active))
    XCTAssertEqual(
      CVSNeuralTransportAvailableOutput(transport),
      UInt32(blockFrames)
    )
    XCTAssertLessThan(
      CVSNeuralTransportInferenceMicroseconds(transport),
      200_000
    )
    let latencyMilliseconds =
      Double(CVSNeuralTransportLatencyFrames(transport)) / 48
    XCTAssertGreaterThanOrEqual(latencyMilliseconds, 340)
    XCTAssertLessThan(latencyMilliseconds, 500)

    var output = [Float](repeating: 0, count: blockFrames)
    XCTAssertEqual(
      output.withUnsafeMutableBufferPointer {
        CVSNeuralTransportPopOutput(
          transport,
          $0.baseAddress!,
          UInt32($0.count)
        )
      },
      UInt32(blockFrames)
    )
    XCTAssertTrue(output.allSatisfy(\.isFinite))
    XCTAssertGreaterThan(output.map(abs).max() ?? 0, 0.001)

    engine.stop()
    XCTAssertTrue(activityRecorder.contains(.off))
  }
}
