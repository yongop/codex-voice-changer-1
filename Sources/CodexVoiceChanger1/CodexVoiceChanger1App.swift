import SwiftUI

@main
struct CodexVoiceChanger1App: App {
  @StateObject private var model = AppModel()

  var body: some Scene {
    WindowGroup {
      ContentView(model: model)
    }
    .windowResizability(.contentSize)
    .commands {
      CommandGroup(after: .appInfo) {
        Divider()
        Button("실행 중인 앱 새로고침") {
          model.refreshApplications()
        }
        .keyboardShortcut("r", modifiers: [.command])
      }
    }
  }
}
