import CoreAudio
import Foundation

@available(macOS 14.2, *)
final class ProcessTapSession {
  let format: AudioStreamBasicDescription
  let aggregateDeviceID: AudioObjectID
  private var tapID: AudioObjectID
  private var isStopped = false

  init(
    pid: pid_t,
    bundleID: String,
    muteOriginal: Bool
  ) throws {
    let catalog = try CoreAudioProcessCatalog.processObjectIDs(
      pid: pid,
      bundleID: bundleID
    )

    if catalog.ids.isEmpty {
      if #unavailable(macOS 26.0) {
        throw VoiceChangerError.noAudioProcess
      }
    }
    let description = CATapDescription()
    description.name = "Codex Voice Changer 1 — \(bundleID)"
    description.processes = catalog.ids
    description.isPrivate = true
    description.isMixdown = true
    description.isMono = false
    description.isExclusive = false
    description.muteBehavior = muteOriginal ? .mutedWhenTapped : .unmuted

    if #available(macOS 26.0, *) {
      description.bundleIDs = catalog.bundleIDs
      description.isProcessRestoreEnabled = true
    }

    var createdTapID = AudioObjectID(kAudioObjectUnknown)
    try requireNoErr(
      AudioHardwareCreateProcessTap(description, &createdTapID),
      .createTap
    )
    guard createdTapID != kAudioObjectUnknown else {
      throw VoiceChangerError.invalidTap
    }
    tapID = createdTapID

    do {
      format = try Self.readTapFormat(tapID: createdTapID)
      let tapUID = try Self.readTapUID(tapID: createdTapID)
      aggregateDeviceID = try Self.createAggregateDevice(tapUID: tapUID)
    } catch {
      AudioHardwareDestroyProcessTap(createdTapID)
      throw error
    }
  }

  deinit {
    stop()
  }

  func stop() {
    guard !isStopped else {
      return
    }
    isStopped = true
    if aggregateDeviceID != kAudioObjectUnknown {
      AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
    }
    if tapID != kAudioObjectUnknown {
      AudioHardwareDestroyProcessTap(tapID)
      tapID = kAudioObjectUnknown
    }
  }

  private static func readTapFormat(
    tapID: AudioObjectID
  ) throws -> AudioStreamBasicDescription {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioTapPropertyFormat,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var value = AudioStreamBasicDescription()
    var byteCount = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    try requireNoErr(
      AudioObjectGetPropertyData(
        tapID,
        &address,
        0,
        nil,
        &byteCount,
        &value
      ),
      .readTapFormat
    )
    guard value.mSampleRate > 0 else {
      throw VoiceChangerError.invalidAudioFormat
    }
    return value
  }

  private static func readTapUID(tapID: AudioObjectID) throws -> String {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioTapPropertyUID,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var value: CFString = "" as CFString
    var byteCount = UInt32(MemoryLayout<CFString>.stride)
    let status = withUnsafeMutablePointer(to: &value) { pointer in
      AudioObjectGetPropertyData(
        tapID,
        &address,
        0,
        nil,
        &byteCount,
        pointer
      )
    }
    try requireNoErr(status, .readTapUID)
    return value as String
  }

  private static func createAggregateDevice(
    tapUID: String
  ) throws -> AudioObjectID {
    let uniqueID = "dev.codexvoicechanger1.aggregate.\(UUID().uuidString)"
    let subTap: [String: Any] = [
      kAudioSubTapUIDKey: tapUID
    ]
    let description: [String: Any] = [
      kAudioAggregateDeviceNameKey: "Codex Voice Changer 1 Capture",
      kAudioAggregateDeviceUIDKey: uniqueID,
      kAudioAggregateDeviceIsPrivateKey: true,
      kAudioAggregateDeviceTapListKey: [subTap],
    ]

    var deviceID = AudioObjectID(kAudioObjectUnknown)
    try requireNoErr(
      AudioHardwareCreateAggregateDevice(
        description as CFDictionary,
        &deviceID
      ),
      .createAggregateDevice
    )
    guard deviceID != kAudioObjectUnknown else {
      throw VoiceChangerError.invalidAggregateDevice
    }
    return deviceID
  }

}
