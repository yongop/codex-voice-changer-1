import Foundation

enum TsukuyomiTermsConsent {
  static let currentRevision = "2026-07-27"
  static let defaultsKey = "tsukuyomiTermsAcceptedRevision"
  static let modelPageURL = URL(
    string: "https://tyc.rei-yumesaki.net/work/software/rvc/"
  )!
  static let termsURL = URL(
    string: "https://tyc.rei-yumesaki.net/work/software/rvc/terms/"
  )!

  static func isAccepted(
    in defaults: UserDefaults = .standard
  ) -> Bool {
    defaults.string(forKey: defaultsKey) == currentRevision
  }

  static func recordAcceptance(
    in defaults: UserDefaults = .standard
  ) {
    defaults.set(currentRevision, forKey: defaultsKey)
  }
}
