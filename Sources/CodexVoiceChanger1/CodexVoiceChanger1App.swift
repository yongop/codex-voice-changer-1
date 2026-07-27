import SwiftUI

@main
struct CodexVoiceChanger1App: App {
  @StateObject private var model = AppModel()

  var body: some Scene {
    WindowGroup {
      ContentView(model: model)
    }
    .defaultSize(width: 500, height: 720)
    .windowResizability(.contentMinSize)
    .commands {
      CommandGroup(after: .appInfo) {
        Divider()
        Button(model.strings.refreshRunningApps) {
          model.refreshApplications()
        }
        .keyboardShortcut("r", modifiers: [.command])
      }
    }
  }
}
