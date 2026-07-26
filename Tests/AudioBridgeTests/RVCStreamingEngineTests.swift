import AudioBridge
import XCTest

@testable import CodexVoiceChanger1

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
    XCTAssertEqual(RVCStreamingEngine.extraContextSeconds, 1.2)
    XCTAssertEqual(RVCStreamingEngine.initialPrimeBlocks, 2)
    XCTAssertEqual(RVCStreamingEngine.maxPrimeBlocks, 5)
    XCTAssertEqual(
      RVCStreamingEngine.adaptivePrimeBlocks(
        observedInferenceMicroseconds: 100_000,
        blockMicroseconds: 220_000
      ),
      2
    )
    XCTAssertEqual(
      RVCStreamingEngine.adaptivePrimeBlocks(
        observedInferenceMicroseconds: 221_000,
        blockMicroseconds: 220_000
      ),
      3
    )
    XCTAssertEqual(
      RVCStreamingEngine.adaptivePrimeBlocks(
        observedInferenceMicroseconds: 500_000,
        blockMicroseconds: 220_000
      ),
      4
    )
    XCTAssertEqual(
      RVCStreamingEngine.adaptivePrimeBlocks(
        observedInferenceMicroseconds: 900_000,
        blockMicroseconds: 220_000
      ),
      5
    )
  }

  func testWorkerIntegrationWhenRequested() throws {
    guard
      ProcessInfo.processInfo.environment[
        "CVS_RUN_RVC_INTEGRATION_TEST"
      ] == "1"
    else {
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
    let initialFeedFrames =
      blockFrames * RVCStreamingEngine.maxPrimeBlocks
    var input = [Float](repeating: 0, count: initialFeedFrames)
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
      UInt32(initialFeedFrames)
    )

    let outputDeadline = Date().addingTimeInterval(6)
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
    let targetFrames = Int(
      CVSNeuralTransportTargetOutputFrames(transport)
    )
    XCTAssertGreaterThanOrEqual(
      targetFrames,
      blockFrames * RVCStreamingEngine.initialPrimeBlocks
    )
    XCTAssertLessThanOrEqual(
      targetFrames,
      blockFrames * RVCStreamingEngine.maxPrimeBlocks
    )
    XCTAssertEqual(targetFrames % blockFrames, 0)
    XCTAssertGreaterThanOrEqual(
      Int(CVSNeuralTransportAvailableOutput(transport)),
      targetFrames
    )
    XCTAssertEqual(
      CVSNeuralTransportMaximumOutputFrames(transport),
      UInt32(blockFrames * RVCStreamingEngine.maxPrimeBlocks)
    )
    XCTAssertLessThan(
      CVSNeuralTransportInferenceMicroseconds(transport),
      200_000
    )
    // The test feeds input faster than real time, so the measured prime
    // latency primarily reflects worker processing time.
    let latencyMilliseconds =
      Double(CVSNeuralTransportLatencyFrames(transport)) / 48
    XCTAssertGreaterThan(latencyMilliseconds, 20)
    XCTAssertLessThan(latencyMilliseconds, 1_500)

    let excessFrames =
      Int(CVSNeuralTransportAvailableOutput(transport)) - targetFrames
    if excessFrames > 0 {
      var excess = [Float](repeating: 0, count: excessFrames)
      XCTAssertEqual(
        excess.withUnsafeMutableBufferPointer {
          CVSNeuralTransportPopOutput(
            transport,
            $0.baseAddress!,
            UInt32($0.count)
          )
        },
        UInt32(excessFrames)
      )
    }

    // Feed and consume 10 ms quanta for exactly 18 worker blocks. The output
    // must retain its adaptive reserve without a single realtime underrun.
    let quantum = 480
    let soakQuanta = 18 * blockFrames / quantum
    var realtimeInput = [Float](repeating: 0, count: quantum)
    var realtimeOutput = [Float](repeating: 0, count: quantum)
    var inputFrame = initialFeedFrames
    var underflows = 0
    var peak: Float = 0
    let soakStart = DispatchTime.now().uptimeNanoseconds
    for quantumIndex in 0..<soakQuanta {
      for frame in realtimeInput.indices {
        realtimeInput[frame] = Float(
          sin(
            2 * Double.pi * 162
              * Double(inputFrame + frame) / 48_000
          ) * 0.08
        )
      }
      inputFrame += quantum
      XCTAssertEqual(
        realtimeInput.withUnsafeBufferPointer {
          CVSNeuralTransportPushInput(
            transport,
            $0.baseAddress!,
            UInt32($0.count)
          )
        },
        UInt32(quantum)
      )
      if CVSNeuralTransportAvailableOutput(transport) >= UInt32(quantum) {
        XCTAssertEqual(
          realtimeOutput.withUnsafeMutableBufferPointer {
            CVSNeuralTransportPopOutput(
              transport,
              $0.baseAddress!,
              UInt32($0.count)
            )
          },
          UInt32(quantum)
        )
        peak = max(peak, realtimeOutput.map(abs).max() ?? 0)
      } else {
        underflows += 1
      }

      let deadline =
        soakStart + UInt64(quantumIndex + 1) * 10_000_000
      let now = DispatchTime.now().uptimeNanoseconds
      if deadline > now {
        Thread.sleep(
          forTimeInterval: Double(deadline - now) / 1_000_000_000
        )
      }
    }
    XCTAssertEqual(underflows, 0)
    XCTAssertEqual(CVSNeuralTransportDroppedInputFrames(transport), 0)
    XCTAssertGreaterThan(peak, 0.001)

    // Let the final speech block finish, drain it, then verify that the third
    // silent block takes the zero-cost bypass after the two-block hangover.
    Thread.sleep(forTimeInterval: 0.3)
    let remainingFrames = Int(
      CVSNeuralTransportAvailableOutput(transport)
    )
    if remainingFrames > 0 {
      var remaining = [Float](repeating: 0, count: remainingFrames)
      _ = remaining.withUnsafeMutableBufferPointer {
        CVSNeuralTransportPopOutput(
          transport,
          $0.baseAddress!,
          UInt32($0.count)
        )
      }
    }

    let silentFrames = blockFrames * 3
    let silence = [Float](repeating: 0, count: silentFrames)
    XCTAssertEqual(
      silence.withUnsafeBufferPointer {
        CVSNeuralTransportPushInput(
          transport,
          $0.baseAddress!,
          UInt32($0.count)
        )
      },
      UInt32(silentFrames)
    )
    let silenceDeadline = Date().addingTimeInterval(2)
    while CVSNeuralTransportAvailableOutput(transport)
      < UInt32(silentFrames),
      Date() < silenceDeadline
    {
      Thread.sleep(forTimeInterval: 0.005)
    }
    XCTAssertGreaterThanOrEqual(
      CVSNeuralTransportAvailableOutput(transport),
      UInt32(silentFrames)
    )
    XCTAssertLessThan(
      CVSNeuralTransportInferenceMicroseconds(transport),
      10_000
    )
    var silentOutput = [Float](repeating: 1, count: silentFrames)
    XCTAssertEqual(
      silentOutput.withUnsafeMutableBufferPointer {
        CVSNeuralTransportPopOutput(
          transport,
          $0.baseAddress!,
          UInt32($0.count)
        )
      },
      UInt32(silentFrames)
    )
    XCTAssertEqual(
      silentOutput.suffix(blockFrames).map(abs).max(),
      0
    )

    engine.stop()
    XCTAssertTrue(activityRecorder.contains(.off))
  }
}
