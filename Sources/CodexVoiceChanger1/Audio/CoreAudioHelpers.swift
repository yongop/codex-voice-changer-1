import CoreAudio
import Foundation

/// The step a Core Audio call was performing, kept as a case rather than a
/// message so the failure reads in whichever language is active when it is
/// shown.
enum CoreAudioOperation {
  case startCapture
  case createTap
  case readTapFormat
  case readTapUID
  case createAggregateDevice
  case findAudioProcess
  case queryProcessListSize
  case readProcessList
  case readProcessBundleID

  var localizedName: String {
    let strings = L.s
    switch self {
    case .startCapture:
      return strings.operationStartCapture
    case .createTap:
      return strings.operationCreateTap
    case .readTapFormat:
      return strings.operationReadTapFormat
    case .readTapUID:
      return strings.operationReadTapUID
    case .createAggregateDevice:
      return strings.operationCreateAggregateDevice
    case .findAudioProcess:
      return strings.operationFindAudioProcess
    case .queryProcessListSize:
      return strings.operationQueryProcessListSize
    case .readProcessList:
      return strings.operationReadProcessList
    case .readProcessBundleID:
      return strings.operationReadProcessBundleID
    }
  }
}

struct CoreAudioFailure: LocalizedError {
  let operation: CoreAudioOperation
  let status: OSStatus

  var errorDescription: String? {
    L.s.coreAudioFailure(
      operation: operation.localizedName,
      code: fourCharacterCode(status),
      status: status
    )
  }
}

@inline(__always)
func requireNoErr(
  _ status: OSStatus,
  _ operation: CoreAudioOperation
) throws {
  guard status == noErr else {
    throw CoreAudioFailure(operation: operation, status: status)
  }
}

private func fourCharacterCode(_ status: OSStatus) -> String {
  let value = UInt32(bitPattern: status)
  let bytes: [UInt8] = [
    UInt8((value >> 24) & 0xff),
    UInt8((value >> 16) & 0xff),
    UInt8((value >> 8) & 0xff),
    UInt8(value & 0xff),
  ]
  if bytes.allSatisfy({ $0 >= 32 && $0 <= 126 }) {
    return "'\(String(bytes: bytes, encoding: .ascii) ?? "????")'"
  }
  return "\(status)"
}

enum CoreAudioProcessCatalog {
  static func processObjectIDs(
    pid: pid_t,
    bundleID: String
  ) throws -> (ids: [AudioObjectID], bundleIDs: [String]) {
    var results = Set<AudioObjectID>()
    var matchingBundleIDs = Set<String>()

    if let translated = try translatePID(pid), translated != kAudioObjectUnknown {
      results.insert(translated)
      if let translatedBundleID = try? stringProperty(
        objectID: translated,
        selector: kAudioProcessPropertyBundleID
      ) {
        matchingBundleIDs.insert(translatedBundleID)
      }
    }

    for processID in try allProcessObjectIDs() {
      guard
        let candidateBundleID = try? stringProperty(
          objectID: processID,
          selector: kAudioProcessPropertyBundleID
        )
      else {
        continue
      }

      // Electron/Chromium helper processes typically add a suffix to the
      // parent app's bundle identifier. Include those audio owners too.
      if candidateBundleID == bundleID
        || candidateBundleID.hasPrefix(bundleID + ".")
      {
        results.insert(processID)
        matchingBundleIDs.insert(candidateBundleID)
      }
    }

    matchingBundleIDs.insert(bundleID)
    return (
      results.sorted(),
      matchingBundleIDs.sorted()
    )
  }

  private static func translatePID(_ pid: pid_t) throws -> AudioObjectID? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var pidCopy = pid
    var processID = AudioObjectID(kAudioObjectUnknown)
    var outputSize = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = withUnsafePointer(to: &pidCopy) { qualifier in
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        UInt32(MemoryLayout<pid_t>.size),
        qualifier,
        &outputSize,
        &processID
      )
    }
    try requireNoErr(status, .findAudioProcess)
    return processID
  }

  private static func allProcessObjectIDs() throws -> [AudioObjectID] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyProcessObjectList,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var byteCount: UInt32 = 0
    try requireNoErr(
      AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &byteCount
      ),
      .queryProcessListSize
    )
    guard byteCount > 0 else {
      return []
    }

    let count = Int(byteCount) / MemoryLayout<AudioObjectID>.stride
    var values = [AudioObjectID](repeating: 0, count: count)
    let status = values.withUnsafeMutableBytes { buffer in
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &byteCount,
        buffer.baseAddress!
      )
    }
    try requireNoErr(status, .readProcessList)
    return Array(values.prefix(Int(byteCount) / MemoryLayout<AudioObjectID>.stride))
  }

  private static func stringProperty(
    objectID: AudioObjectID,
    selector: AudioObjectPropertySelector
  ) throws -> String {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var byteCount = UInt32(MemoryLayout<CFString>.stride)
    var value: CFString = "" as CFString
    let status = withUnsafeMutablePointer(to: &value) { pointer in
      AudioObjectGetPropertyData(
        objectID,
        &address,
        0,
        nil,
        &byteCount,
        pointer
      )
    }
    try requireNoErr(status, .readProcessBundleID)
    return value as String
  }
}
