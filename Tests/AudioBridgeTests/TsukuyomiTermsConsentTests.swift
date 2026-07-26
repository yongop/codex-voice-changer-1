import Foundation
import XCTest
@testable import CodexVoiceChanger1

final class TsukuyomiTermsConsentTests: XCTestCase {
  func testAcceptanceRequiresCurrentRevision() throws {
    let suiteName = "TsukuyomiTermsConsentTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }

    XCTAssertFalse(TsukuyomiTermsConsent.isAccepted(in: defaults))

    defaults.set(
      "older-revision",
      forKey: TsukuyomiTermsConsent.defaultsKey
    )
    XCTAssertFalse(TsukuyomiTermsConsent.isAccepted(in: defaults))

    TsukuyomiTermsConsent.recordAcceptance(in: defaults)
    XCTAssertTrue(TsukuyomiTermsConsent.isAccepted(in: defaults))
    XCTAssertEqual(
      defaults.string(forKey: TsukuyomiTermsConsent.defaultsKey),
      TsukuyomiTermsConsent.currentRevision
    )
  }
}
