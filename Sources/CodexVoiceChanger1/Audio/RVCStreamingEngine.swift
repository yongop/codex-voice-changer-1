import AudioBridge
import Foundation

enum RVCActivityState: Equatable, Sendable {
  case off
  case preparing
  case active
  case failed
}

private enum RVCStreamingError: LocalizedError {
  case runtimeNotFound(String)
  case workerProtocol(String)
  case invalidOutput

  var errorDescription: String? {
    switch self {
    case .runtimeNotFound(let detail):
      return "RVC 런타임을 찾지 못했습니다: \(detail)"
    case .workerProtocol(let detail):
      return "RVC 작업자 통신에 실패했습니다: \(detail)"
    case .invalidOutput:
      return "RVC 작업자가 유효하지 않은 오디오를 반환했습니다."
    }
  }
}

private final class RVCWorkerCancellationToken {
  private let lock = NSLock()
  private var cancelled = false

  func cancel() {
    lock.lock()
    cancelled = true
    lock.unlock()
  }

  var isCancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelled
  }
}

private struct RVCResourcePaths {
  let python: URL
  let worker: URL
  let runtimeRoot: URL
  let model: URL
}

@available(macOS 14.2, *)
final class RVCStreamingEngine {
  static let blockSeconds = 0.22
  static let crossfadeSeconds = 0.05
  static let extraContextSeconds = 2.5
  static let pitchShiftSemitones = 5
  static let schedulingReserveSeconds = 0.06

  private let transport: OpaquePointer
  private let sampleRate: Double
  private let onActivityChange: @Sendable (RVCActivityState) -> Void
  private let queue = DispatchQueue(
    label: "dev.codexvoicechanger1.tsukuyomi-rvc",
    qos: .userInteractive
  )
  private let completion = DispatchGroup()
  private let processLock = NSLock()
  private var process: Process?
  private var token: RVCWorkerCancellationToken?

  init(
    transport: OpaquePointer,
    sampleRate: Double,
    onActivityChange: @escaping @Sendable (RVCActivityState) -> Void = {
      _ in
    }
  ) {
    self.transport = transport
    self.sampleRate = sampleRate
    self.onActivityChange = onActivityChange
  }

  func start() {
    if token != nil {
      stop()
    }
    let nextToken = RVCWorkerCancellationToken()
    token = nextToken
    // Replaced by block + measured inference + reserve after warm-up.
    CVSNeuralTransportSetMetrics(
      transport,
      UInt32(ceil(sampleRate * 0.42)),
      0
    )
    publishStatus(CVSNeuralStatusLoading, activity: .preparing)
    let completion = completion
    completion.enter()
    queue.async { [weak self] in
      defer { completion.leave() }
      self?.run(token: nextToken)
    }
  }

  func stop() {
    guard let token else {
      publishStatus(CVSNeuralStatusDisabled, activity: .off)
      return
    }
    token.cancel()
    processLock.lock()
    let runningProcess = process
    processLock.unlock()
    if let runningProcess, runningProcess.isRunning {
      runningProcess.terminate()
    }
    completion.wait()
    self.token = nil
    publishStatus(CVSNeuralStatusDisabled, activity: .off)
  }

  private func run(token: RVCWorkerCancellationToken) {
    do {
      guard !token.isCancelled else { return }
      let resources = try Self.resourcePaths()
      guard !token.isCancelled else { return }
      let workerProcess = Process()
      let inputPipe = Pipe()
      let outputPipe = Pipe()
      let errorPipe = Pipe()
      workerProcess.executableURL = resources.python
      workerProcess.arguments = [
        "-B",
        resources.worker.path,
        "--rvc-root", resources.runtimeRoot.path,
        "--model", resources.model.path,
        "--sample-rate", String(Int(sampleRate.rounded())),
        "--pitch", String(Self.pitchShiftSemitones),
        "--block-seconds", String(Self.blockSeconds),
        "--crossfade-seconds", String(Self.crossfadeSeconds),
        "--extra-seconds", String(Self.extraContextSeconds),
        "--warmup-iterations", "3",
      ]
      var environment = ProcessInfo.processInfo.environment
      environment["PYTHONUNBUFFERED"] = "1"
      environment["PYTHONDONTWRITEBYTECODE"] = "1"
      environment["PYTORCH_ENABLE_MPS_FALLBACK"] = "1"
      environment["TOKENIZERS_PARALLELISM"] = "false"
      workerProcess.environment = environment
      workerProcess.standardInput = inputPipe
      workerProcess.standardOutput = outputPipe
      workerProcess.standardError = errorPipe
      errorPipe.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        guard !data.isEmpty,
          let message = String(data: data, encoding: .utf8)
        else {
          return
        }
        NSLog("Tsukuyomi RVC: %@", message.trimmingCharacters(in: .whitespacesAndNewlines))
      }

      processLock.lock()
      process = workerProcess
      processLock.unlock()
      guard !token.isCancelled else {
        errorPipe.fileHandleForReading.readabilityHandler = nil
        processLock.lock()
        process = nil
        processLock.unlock()
        return
      }
      try workerProcess.run()
      defer {
        errorPipe.fileHandleForReading.readabilityHandler = nil
        try? inputPipe.fileHandleForWriting.close()
        try? outputPipe.fileHandleForReading.close()
        if workerProcess.isRunning {
          workerProcess.terminate()
        }
        workerProcess.waitUntilExit()
        processLock.lock()
        process = nil
        processLock.unlock()
      }

      let ready = try Self.readExactly(
        count: 12,
        from: outputPipe.fileHandleForReading
      )
      guard ready.prefix(4) == Data("RDY1".utf8) else {
        throw try Self.protocolError(from: ready, handle: outputPipe.fileHandleForReading)
      }
      let workerRate = Self.uint32LE(ready, offset: 4)
      let blockFrames = Int(Self.uint32LE(ready, offset: 8))
      guard workerRate == UInt32(sampleRate.rounded()),
        blockFrames > 0
      else {
        throw RVCStreamingError.workerProtocol(
          "샘플레이트 또는 블록 크기 불일치"
        )
      }
      guard !token.isCancelled else { return }

      CVSNeuralTransportDiscardInput(transport)
      CVSNeuralTransportRequestOutputDiscard(transport)
      publishStatus(CVSNeuralStatusWarmingUp, activity: .preparing)
      try stream(
        process: workerProcess,
        input: inputPipe.fileHandleForWriting,
        output: outputPipe.fileHandleForReading,
        blockFrames: blockFrames,
        token: token
      )
    } catch {
      guard !token.isCancelled else { return }
      NSLog("Tsukuyomi RVC engine failed: %@", error.localizedDescription)
      publishStatus(CVSNeuralStatusFailed, activity: .failed)
    }
  }

  private func stream(
    process: Process,
    input: FileHandle,
    output: FileHandle,
    blockFrames: Int,
    token: RVCWorkerCancellationToken
  ) throws {
    var inputBlock = [Float](repeating: 0, count: blockFrames)
    var outputBlock = [Float](repeating: 0, count: blockFrames)
    let blockNanoseconds = UInt64(
      Double(blockFrames) / sampleRate * 1_000_000_000
    )
    var presentationNanoseconds = UInt64(420_000_000)
    var producedOutput = false

    while !token.isCancelled && process.isRunning {
      if CVSNeuralTransportTakeStreamResetRequest(transport) {
        try input.write(contentsOf: Data("RST1".utf8))
        let response = try Self.readExactly(count: 4, from: output)
        guard response == Data("ACK1".utf8) else {
          throw try Self.protocolError(from: response, handle: output)
        }
        CVSNeuralTransportDiscardInput(transport)
        CVSNeuralTransportRequestOutputDiscard(transport)
        publishStatus(CVSNeuralStatusWarmingUp, activity: .preparing)
        producedOutput = false
        presentationNanoseconds = UInt64(420_000_000)
      }

      guard CVSNeuralTransportAvailableInput(transport) >= blockFrames else {
        let available = CVSNeuralTransportAvailableInput(transport)
        let missing = max(0, blockFrames - Int(available))
        let wait = min(
          0.005,
          max(0.001, Double(missing) / sampleRate * 0.5)
        )
        Thread.sleep(forTimeInterval: wait)
        continue
      }
      let popped = inputBlock.withUnsafeMutableBufferPointer { pointer in
        CVSNeuralTransportPopInput(
          transport,
          pointer.baseAddress!,
          UInt32(blockFrames)
        )
      }
      guard popped == blockFrames else {
        continue
      }

      var request = Data("FRM1".utf8)
      inputBlock.withUnsafeBytes { request.append(contentsOf: $0) }
      let started = DispatchTime.now().uptimeNanoseconds
      try input.write(contentsOf: request)

      let response = try Self.readExactly(count: 8, from: output)
      guard response.prefix(4) == Data("OUT1".utf8) else {
        throw try Self.protocolError(from: response, handle: output)
      }
      let inferenceMicroseconds = Self.uint32LE(response, offset: 4)
      let pcm = try Self.readExactly(
        count: blockFrames * MemoryLayout<Float>.size,
        from: output
      )
      _ = outputBlock.withUnsafeMutableBytes { destination in
        pcm.copyBytes(to: destination)
      }
      guard outputBlock.allSatisfy(\.isFinite) else {
        throw RVCStreamingError.invalidOutput
      }

      let pushed = outputBlock.withUnsafeBufferPointer { pointer in
        CVSNeuralTransportPushOutput(
          transport,
          pointer.baseAddress!,
          UInt32(blockFrames)
        )
      }
      guard pushed == blockFrames else {
        CVSNeuralTransportRequestStreamReset(transport)
        continue
      }

      if !producedOutput {
        let inferenceNanoseconds =
          DispatchTime.now().uptimeNanoseconds - started
        presentationNanoseconds = max(
          UInt64(320_000_000),
          blockNanoseconds + inferenceNanoseconds
            + UInt64(
              Self.schedulingReserveSeconds * 1_000_000_000
            )
        )
        producedOutput = true
        Thread.sleep(forTimeInterval: Self.schedulingReserveSeconds)
      }
      let latencyFrames = UInt32(
        min(
          ceil(
            Double(presentationNanoseconds) / 1_000_000_000 * sampleRate
          ),
          Double(UInt32.max)
        )
      )
      CVSNeuralTransportSetMetrics(
        transport,
        latencyFrames,
        inferenceMicroseconds
      )
      if CVSNeuralTransportGetStatus(transport)
        == CVSNeuralStatusWarmingUp
      {
        publishStatus(CVSNeuralStatusReady, activity: .active)
      }
    }
  }

  private func publishStatus(
    _ status: CVSNeuralStatus,
    activity: RVCActivityState
  ) {
    CVSNeuralTransportSetStatus(transport, status)
    onActivityChange(activity)
  }

  private static func readExactly(
    count: Int,
    from handle: FileHandle
  ) throws -> Data {
    var result = Data()
    result.reserveCapacity(count)
    while result.count < count {
      guard let block = try handle.read(
        upToCount: count - result.count
      ), !block.isEmpty
      else {
        throw RVCStreamingError.workerProtocol("예기치 않은 EOF")
      }
      result.append(block)
    }
    return result
  }

  private static func uint32LE(
    _ data: Data,
    offset: Int
  ) -> UInt32 {
    precondition(offset >= 0 && offset + 4 <= data.count)
    return UInt32(data[offset])
      | UInt32(data[offset + 1]) << 8
      | UInt32(data[offset + 2]) << 16
      | UInt32(data[offset + 3]) << 24
  }

  private static func protocolError(
    from header: Data,
    handle: FileHandle
  ) throws -> RVCStreamingError {
    if header.prefix(4) == Data("ERR1".utf8), header.count >= 8 {
      let length = Int(uint32LE(header, offset: 4))
      let message = try readExactly(count: length, from: handle)
      return .workerProtocol(
        String(data: message, encoding: .utf8) ?? "작업자 오류"
      )
    }
    let value = String(data: header.prefix(4), encoding: .ascii) ?? "binary"
    return .workerProtocol("예상하지 못한 응답 \(value)")
  }

  private static func resourcePaths() throws -> RVCResourcePaths {
    let environment = ProcessInfo.processInfo.environment
    let sourceRoot =
      URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let bundledRVC = Bundle.main.resourceURL?
      .appendingPathComponent("RVC", isDirectory: true)
    let projectFromApp = Bundle.main.bundleURL
      .deletingLastPathComponent()
      .deletingLastPathComponent()

    let pythonCandidates = [
      environment["CVS_RVC_PYTHON"].map(URL.init(fileURLWithPath:)),
      bundledRVC?.appendingPathComponent("python/bin/python"),
      sourceRoot.appendingPathComponent(".rvc_env/bin/python"),
      projectFromApp.appendingPathComponent(".rvc_env/bin/python"),
    ].compactMap { $0 }
    let workerCandidates = [
      environment["CVS_RVC_WORKER_PATH"].map(URL.init(fileURLWithPath:)),
      bundledRVC?.appendingPathComponent("rvc_stream_worker.py"),
      sourceRoot.appendingPathComponent(
        "Runtime/rvc_stream_worker.py"
      ),
    ].compactMap { $0 }
    let runtimeCandidates = [
      environment["CVS_RVC_ROOT"].map(URL.init(fileURLWithPath:)),
      bundledRVC?.appendingPathComponent("runtime", isDirectory: true),
      sourceRoot.appendingPathComponent(
        ".training_cache/tsukuyomi_rvc/RVC",
        isDirectory: true
      ),
    ].compactMap { $0 }
    let modelCandidates = [
      environment["CVS_RVC_MODEL_PATH"].map(URL.init(fileURLWithPath:)),
      bundledRVC?.appendingPathComponent("tsukuyomi_01.pth"),
      sourceRoot.appendingPathComponent(
        ".training_cache/tsukuyomi_rvc/models/tsukuyomi_01.pth"
      ),
    ].compactMap { $0 }

    guard let python = firstExisting(pythonCandidates) else {
      throw RVCStreamingError.runtimeNotFound(".rvc_env/bin/python")
    }
    guard let worker = firstExisting(workerCandidates) else {
      throw RVCStreamingError.runtimeNotFound("rvc_stream_worker.py")
    }
    guard let runtimeRoot = firstExisting(runtimeCandidates) else {
      throw RVCStreamingError.runtimeNotFound("RVC runtime")
    }
    guard let model = firstExisting(modelCandidates) else {
      throw RVCStreamingError.runtimeNotFound("tsukuyomi_01.pth")
    }
    return RVCResourcePaths(
      python: python,
      worker: worker,
      runtimeRoot: runtimeRoot,
      model: model
    )
  }

  private static func firstExisting(_ candidates: [URL]) -> URL? {
    candidates.first {
      FileManager.default.fileExists(atPath: $0.path)
    }
  }
}
