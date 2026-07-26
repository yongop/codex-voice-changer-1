import AppKit
import Foundation

struct TargetApplication: Identifiable, Hashable {
  let name: String
  let bundleID: String
  let pid: pid_t
  let icon: NSImage?

  var id: String {
    bundleID
  }

  static func == (
    lhs: TargetApplication,
    rhs: TargetApplication
  ) -> Bool {
    lhs.bundleID == rhs.bundleID && lhs.pid == rhs.pid
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(bundleID)
    hasher.combine(pid)
  }
}
