import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: NSObject, ObservableObject {
  @Published private(set) var applications: [TargetApplication] = []
  @Published var selectedBundleID = ""
  @Published private(set) var isRunning = false
  @Published private(set) var rvcActivity: RVCActivityState = .off
  @Published var errorText: String?

  private var pipeline: AudioPipeline?
  private var pipelineGeneration = UUID()
  private var workspaceObservers: [NSObjectProtocol] = []

  override init() {
    super.init()
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

  func start() {
    guard let target = selectedApplication else {
      errorText = "먼저 캡처할 앱을 선택해 주세요."
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
    let candidates = [
      "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture",
      "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
      "x-apple.systempreferences:com.apple.preference.security",
    ]
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
