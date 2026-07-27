import Foundation

/// Every user-facing string in the app, in one language.
///
/// The app ships its own tables instead of `.lproj` bundles because the
/// executable is packaged by `Scripts/build-app.sh` rather than by Xcode, and
/// because the display language is user-selectable at runtime instead of being
/// fixed to the macOS preferred-language order.
protocol AppStringsProviding: Sendable {
  // MARK: Language selection

  var languageMenuTitle: String { get }
  var languageSystemOption: String { get }

  // MARK: Main window

  var errorAlertTitle: String { get }
  var okButton: String { get }
  var captureTargetTitle: String { get }
  var refreshRunningApps: String { get }

  var activityOff: String { get }
  var activityPreparing: String { get }
  var activityActive: String { get }
  var activityFailed: String { get }

  // MARK: Terms consent

  var consentTitle: String { get }
  var consentBody: String { get }
  var consentChecklistTitle: String { get }
  var consentChecklistCredit: String { get }
  var consentChecklistRights: String { get }
  var consentChecklistPriority: String { get }
  var consentOpenModelPage: String { get }
  var consentOpenTerms: String { get }
  var consentAcceptButton: String { get }
  func consentRecordNote(revision: String) -> String

  // MARK: Voice credit

  var creditIncluded: String { get }
  var creditVoice: String { get }
  var creditModelPage: String { get }
  var creditTerms: String { get }
  var creditCompliance: String { get }
  var creditAccessibility: String { get }

  // MARK: Setup guide

  var setupSectionTitle: String { get }
  var setupHint: String { get }
  var setupOpenAudioPrivacy: String { get }
  var setupOpenFilesPrivacy: String { get }
  var setupStep1Title: String { get }
  var setupStep1Detail: String { get }
  var setupStep2Title: String { get }
  var setupStep2Detail: String { get }
  var setupStep3Title: String { get }
  var setupStep3Detail: String { get }
  var setupStep4Title: String { get }
  var setupStep4Detail: String { get }
  var setupStep5Title: String { get }
  var setupStep5Detail: String { get }
  func setupStepAccessibilityLabel(index: Int, title: String) -> String

  // MARK: Errors

  var errorTermsRequired: String { get }
  var errorSelectTargetApp: String { get }
  var errorUnsupportedSystem: String { get }
  var errorNoAudioProcess: String { get }
  var errorInvalidTap: String { get }
  var errorInvalidAggregateDevice: String { get }
  var errorInvalidAudioFormat: String { get }
  var errorBufferAllocation: String { get }
  var errorProcessorAllocation: String { get }

  // MARK: Core Audio operations

  var operationStartCapture: String { get }
  var operationCreateTap: String { get }
  var operationReadTapFormat: String { get }
  var operationReadTapUID: String { get }
  var operationCreateAggregateDevice: String { get }
  var operationFindAudioProcess: String { get }
  var operationQueryProcessListSize: String { get }
  var operationReadProcessList: String { get }
  var operationReadProcessBundleID: String { get }
  func coreAudioFailure(
    operation: String,
    code: String,
    status: Int32
  ) -> String
}

/// Holds the string table for the active language.
///
/// Error descriptions are read wherever `localizedDescription` is called, which
/// is not always the main actor, so the table is guarded by a lock instead of
/// being isolated to `@MainActor`.
enum L {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var storage: any AppStringsProviding =
    AppLanguage.stored().strings

  /// Strings for the language the user is currently reading.
  static var s: any AppStringsProviding {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }

  static func update(to language: AppLanguage) {
    let strings = language.strings
    lock.lock()
    storage = strings
    lock.unlock()
  }
}
