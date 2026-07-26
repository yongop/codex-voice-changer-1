import AudioBridge
import Darwin
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
  static let extraContextSeconds = 1.2
  static let pitchShiftSemitones = 5
  static let initialPrimeBlocks = 2
  static let maxPrimeBlocks = 5

  static func adaptivePrimeBlocks(
    observedInferenceMicroseconds: UInt32,
    blockMicroseconds: UInt32
  ) -> Int {
    guard blockMicroseconds > 0 else {
      return maxPrimeBlocks
    }
    let observedBlocks = Int(
      (UInt64(observedInferenceMicroseconds)
        + UInt64(blockMicroseconds) - 1) / UInt64(blockMicroseconds)
    )
    return min(
      maxPrimeBlocks,
      max(initialPrimeBlocks, observedBlocks + 1)
    )
  }

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
    // Rough dry-alignment estimate until the primed latency is measured:
    // prime depth plus a typical warm inference and scheduling overhead.
    let estimatedLatencySeconds =
      Double(Self.initialPrimeBlocks) * Self.blockSeconds + 0.16
    CVSNeuralTransportSetMetrics(
      transport,
      UInt32(ceil(sampleRate * estimatedLatencySeconds)),
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

      let readyHeader = try Self.readExactly(
        count: 8,
        from: outputPipe.fileHandleForReading
      )
      let readyMagic = readyHeader.prefix(4)
      if readyMagic == Data("ERR1".utf8) {
        throw try Self.protocolError(
          from: readyHeader,
          handle: outputPipe.fileHandleForReading
        )
      }
      guard
        readyMagic == Data("RDY1".utf8)
          || readyMagic == Data("RDY2".utf8)
      else {
        throw try Self.protocolError(
          from: readyHeader,
          handle: outputPipe.fileHandleForReading
        )
      }
      let workerRate = Self.uint32LE(readyHeader, offset: 4)
      let blockSize = try Self.readExactly(
        count: 4,
        from: outputPipe.fileHandleForReading
      )
      let blockFrames = Int(Self.uint32LE(blockSize, offset: 0))
      let stableWarmupMicroseconds: UInt32
      if readyMagic == Data("RDY2".utf8) {
        let warmup = try Self.readExactly(
          count: 4,
          from: outputPipe.fileHandleForReading
        )
        stableWarmupMicroseconds = Self.uint32LE(warmup, offset: 0)
      } else {
        stableWarmupMicroseconds = 0
      }
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
        stableWarmupMicroseconds: stableWarmupMicroseconds,
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
    stableWarmupMicroseconds: UInt32,
    token: RVCWorkerCancellationToken
  ) throws {
    var inputBlock = [Float](repeating: 0, count: blockFrames)
    var outputBlock = [Float](repeating: 0, count: blockFrames)
    let frameCommand = Array("FRM1".utf8)
    let resetCommand = Array("RST1".utf8)
    var responseHeader = [UInt8](repeating: 0, count: 8)
    guard fcntl(input.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
      throw RVCStreamingError.workerProtocol(
        "파이프 설정 오류: \(String(cString: strerror(errno)))"
      )
    }
    // The output ring is primed with several converted blocks before playback
    // switches away from the dry fallback. That primed depth is the jitter
    // budget every later block's inference time may consume without causing
    // an audible dropout.
    let blockMicroseconds = UInt32(
      min(
        ceil(Double(blockFrames) / sampleRate * 1_000_000),
        Double(UInt32.max)
      )
    )
    var primeTargetBlocks = Self.adaptivePrimeBlocks(
      observedInferenceMicroseconds: stableWarmupMicroseconds,
      blockMicroseconds: blockMicroseconds
    )
    var primed = false
    var latencyFrames: UInt32 = 0
    var epoch = DispatchTime.now()
    var maximumObservedInferenceMicroseconds =
      stableWarmupMicroseconds
    let maximumTargetFrames = UInt32(
      min(
        UInt64(Self.maxPrimeBlocks) * UInt64(blockFrames),
        UInt64(UInt32.max)
      )
    )
    func publishBufferTarget() {
      let targetFrames = UInt32(
        min(
          UInt64(primeTargetBlocks) * UInt64(blockFrames),
          UInt64(UInt32.max)
        )
      )
      CVSNeuralTransportSetOutputBufferTargets(
        transport,
        targetFrames,
        maximumTargetFrames
      )
    }
    publishBufferTarget()

    while !token.isCancelled && process.isRunning {
      if CVSNeuralTransportTakeStreamResetRequest(transport) {
        try resetCommand.withUnsafeBytes {
          try Self.writeExactly($0, to: input)
        }
        let response = try Self.readExactly(count: 4, from: output)
        guard response == Data("ACK1".utf8) else {
          throw try Self.protocolError(from: response, handle: output)
        }
        CVSNeuralTransportDiscardInput(transport)
        CVSNeuralTransportRequestOutputDiscard(transport)
        publishStatus(CVSNeuralStatusWarmingUp, activity: .preparing)
        // A mid-stream rebuild means the previous margin was too thin for
        // this machine's load, so prime one block deeper each time.
        primeTargetBlocks = min(primeTargetBlocks + 1, Self.maxPrimeBlocks)
        primed = false
        epoch = DispatchTime.now()
        maximumObservedInferenceMicroseconds =
          stableWarmupMicroseconds
        publishBufferTarget()
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

      try frameCommand.withUnsafeBytes {
        try Self.writeExactly($0, to: input)
      }
      try inputBlock.withUnsafeBytes {
        try Self.writeExactly($0, to: input)
      }

      try responseHeader.withUnsafeMutableBytes {
        try Self.readExactly(into: $0, from: output)
      }
      guard responseHeader[0] == 0x4f,
        responseHeader[1] == 0x55,
        responseHeader[2] == 0x54,
        responseHeader[3] == 0x31
      else {
        throw try Self.protocolError(
          from: Data(responseHeader),
          handle: output
        )
      }
      let inferenceMicroseconds =
        UInt32(responseHeader[4])
        | UInt32(responseHeader[5]) << 8
        | UInt32(responseHeader[6]) << 16
        | UInt32(responseHeader[7]) << 24
      maximumObservedInferenceMicroseconds = max(
        maximumObservedInferenceMicroseconds,
        inferenceMicroseconds
      )
      try outputBlock.withUnsafeMutableBytes {
        try Self.readExactly(into: $0, from: output)
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

      if primed {
        CVSNeuralTransportSetMetrics(
          transport,
          latencyFrames,
          inferenceMicroseconds
        )
      } else if CVSNeuralTransportAvailableOutput(transport)
        >= CVSNeuralTransportTargetOutputFrames(transport)
      {
        // A slow first live block is a better predictor of the current
        // machine/load than a fixed hardware-name table. Keep one full block
        // beyond the observed inference span, up to the bounded ring budget.
        let adaptiveTarget = Self.adaptivePrimeBlocks(
          observedInferenceMicroseconds:
            maximumObservedInferenceMicroseconds,
          blockMicroseconds: blockMicroseconds
        )
        if adaptiveTarget > primeTargetBlocks {
          primeTargetBlocks = adaptiveTarget
          publishBufferTarget()
          continue
        }
        // The primed depth is complete. Every buffered frame stays exactly
        // (now - epoch) behind its capture time from here on, so that
        // measured interval is the constant presentation latency the dry
        // fallback must match for aligned crossfades.
        let elapsedSeconds =
          Double(
            DispatchTime.now().uptimeNanoseconds - epoch.uptimeNanoseconds
          ) / 1_000_000_000
        latencyFrames = UInt32(
          min(
            ceil(elapsedSeconds * sampleRate),
            Double(UInt32.max)
          )
        )
        primed = true
        CVSNeuralTransportSetMetrics(
          transport,
          latencyFrames,
          inferenceMicroseconds
        )
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
      guard
        let block = try handle.read(
          upToCount: count - result.count
        ), !block.isEmpty
      else {
        throw RVCStreamingError.workerProtocol("예기치 않은 EOF")
      }
      result.append(block)
    }
    return result
  }

  private static func readExactly(
    into buffer: UnsafeMutableRawBufferPointer,
    from handle: FileHandle
  ) throws {
    guard let baseAddress = buffer.baseAddress else {
      return
    }
    var offset = 0
    while offset < buffer.count {
      let count = Darwin.read(
        handle.fileDescriptor,
        baseAddress.advanced(by: offset),
        buffer.count - offset
      )
      if count > 0 {
        offset += count
        continue
      }
      if count < 0 && errno == EINTR {
        continue
      }
      if count == 0 {
        throw RVCStreamingError.workerProtocol("예기치 않은 EOF")
      }
      throw RVCStreamingError.workerProtocol(
        "파이프 읽기 오류: \(String(cString: strerror(errno)))"
      )
    }
  }

  private static func writeExactly(
    _ buffer: UnsafeRawBufferPointer,
    to handle: FileHandle
  ) throws {
    guard let baseAddress = buffer.baseAddress else {
      return
    }
    var offset = 0
    while offset < buffer.count {
      let count = Darwin.write(
        handle.fileDescriptor,
        baseAddress.advanced(by: offset),
        buffer.count - offset
      )
      if count > 0 {
        offset += count
        continue
      }
      if count < 0 && errno == EINTR {
        continue
      }
      throw RVCStreamingError.workerProtocol(
        "파이프 쓰기 오류: \(String(cString: strerror(errno)))"
      )
    }
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
      var message = Data(header.dropFirst(8).prefix(length))
      if message.count < length {
        message.append(
          try readExactly(
            count: length - message.count,
            from: handle
          )
        )
      }
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
