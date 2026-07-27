import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: NSObject, ObservableObject {
  @Published private(set) var applications: [TargetApplication] = []
  @Published var selectedBundleID = ""
  @Published private(set) var isRunning = false
  @Published private(set) var rvcActivity: RVCActivityState = .off
  @Published private(set) var hasAcceptedTerms = false
  @Published var errorText: String?
  @Published var language: AppLanguage = .system {
    didSet {
      guard language != oldValue else { return }
      AppLanguage.save(language)
      L.update(to: language)
    }
  }

  private var pipeline: AudioPipeline?
  private var pipelineGeneration = UUID()
  private var workspaceObservers: [NSObjectProtocol] = []

  override init() {
    hasAcceptedTerms = TsukuyomiTermsConsent.isAccepted()
    super.init()
    language = AppLanguage.stored()
    L.update(to: language)
    selectedBundleID =
      UserDefaults.standard.string(forKey: "targetBundleID") ?? ""
    refreshApplications()
    registerObservers()
  }

  deinit {
    for observer in workspaceObservers {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  /// Strings for the language the user is currently reading.
  var strings: any AppStringsProviding {
    language.strings
  }

  var selectedApplication: TargetApplication? {
    applications.first { $0.bundleID == selectedBundleID }
  }

  func refreshApplications() {
    let ownBundleID = Bundle.main.bundleIdentifier
    var seen = Set<String>()
    let values = NSWorkspace.shared.runningApplications.compactMap {
      application -> TargetApplication? in
      guard application.activationPolicy == .regular,
        let bundleID = application.bundleIdentifier,
        bundleID != ownBundleID,
        seen.insert(bundleID).inserted
      else {
        return nil
      }
      return TargetApplication(
        name: application.localizedName ?? bundleID,
        bundleID: bundleID,
        pid: application.processIdentifier,
        icon: application.icon
      )
    }
    applications = values.sorted { lhs, rhs in
      let lhsPriority = targetPriority(lhs)
      let rhsPriority = targetPriority(rhs)
      if lhsPriority != rhsPriority {
        return lhsPriority < rhsPriority
      }
      return lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        == .orderedAscending
    }

    if !applications.contains(where: { $0.bundleID == selectedBundleID })
      && !isRunning
    {
      selectedBundleID =
        applications.first(where: { targetPriority($0) == 0 })?.bundleID
        ?? applications.first?.bundleID
        ?? ""
    }
    saveTarget()
  }

  func toggleRunning() {
    isRunning ? stop() : start()
  }

  func acceptTerms() {
    TsukuyomiTermsConsent.recordAcceptance()
    hasAcceptedTerms = true
  }

  func start() {
    guard hasAcceptedTerms else {
      errorText = strings.errorTermsRequired
      return
    }
    guard let target = selectedApplication else {
      errorText = strings.errorSelectTargetApp
      return
    }

    errorText = nil
    let generation = UUID()
    pipelineGeneration = generation
    rvcActivity = .preparing
    let candidate = AudioPipeline()
    do {
      try candidate.start(
        pid: target.pid,
        bundleID: target.bundleID,
        onActivityChange: { [weak self] activity in
          Task { @MainActor [weak self] in
            guard let self,
              self.pipelineGeneration == generation
            else {
              return
            }
            self.rvcActivity = activity
          }
        }
      )
      pipeline = candidate
      isRunning = true
      saveTarget()
    } catch {
      candidate.stop()
      pipeline = nil
      isRunning = false
      pipelineGeneration = UUID()
      rvcActivity = .off
      errorText =
        (error as? LocalizedError)?.errorDescription
        ?? error.localizedDescription
    }
  }

  func stop() {
    pipelineGeneration = UUID()
    pipeline?.stop()
    pipeline = nil
    isRunning = false
    rvcActivity = .off
  }

  func openAudioPrivacySettings() {
    openPrivacySettings([
      "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture",
      "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
      "x-apple.systempreferences:com.apple.preference.security",
    ])
  }

  func openFilesPrivacySettings() {
    openPrivacySettings([
      "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders",
      "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
      "x-apple.systempreferences:com.apple.preference.security",
    ])
  }

  private func openPrivacySettings(_ candidates: [String]) {
    for value in candidates {
      if let url = URL(string: value), NSWorkspace.shared.open(url) {
        return
      }
    }
  }

  private func registerObservers() {
    let center = NSWorkspace.shared.notificationCenter
    for name in [
      NSWorkspace.didLaunchApplicationNotification,
      NSWorkspace.didTerminateApplicationNotification,
    ] {
      workspaceObservers.append(
        center.addObserver(
          forName: name,
          object: nil,
          queue: .main
        ) { [weak self] _ in
          Task { @MainActor [weak self] in
            self?.refreshApplications()
          }
        }
      )
    }

    workspaceObservers.append(
      NotificationCenter.default.addObserver(
        forName: NSApplication.willTerminateNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.stop()
        }
      }
    )
  }

  private func targetPriority(_ application: TargetApplication) -> Int {
    let id = application.bundleID.lowercased()
    let name = application.name.lowercased()
    if id == "com.openai.codex" {
      return 0
    }
    if id.contains("codex") || name.contains("codex") {
      return 1
    }
    if id.contains("openai") || name.contains("chatgpt") {
      return 2
    }
    return 3
  }

  private func saveTarget() {
    UserDefaults.standard.set(
      selectedBundleID,
      forKey: "targetBundleID"
    )
  }
}
