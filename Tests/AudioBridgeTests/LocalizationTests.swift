import Foundation
import XCTest

@testable import CodexVoiceChanger1

final class LocalizationTests: XCTestCase {
  func testSystemPreferredPicksFirstSupportedLanguage() {
    XCTAssertEqual(
      AppLanguage.systemPreferred(from: ["ko-KR", "en-US"]),
      .korean
    )
    XCTAssertEqual(
      AppLanguage.systemPreferred(from: ["ja-JP"]),
      .japanese
    )
    XCTAssertEqual(
      AppLanguage.systemPreferred(from: ["en-GB", "ko-KR"]),
      .english
    )
    XCTAssertEqual(
      AppLanguage.systemPreferred(from: ["fr-FR", "ja-JP"]),
      .japanese
    )
  }

  func testSystemPreferredFallsBackToEnglish() {
    XCTAssertEqual(AppLanguage.systemPreferred(from: []), .english)
    XCTAssertEqual(
      AppLanguage.systemPreferred(from: ["fr-FR", "de-DE"]),
      .english
    )
    XCTAssertEqual(AppLanguage.systemPreferred(from: ["not-a-locale"]), .english)
  }

  func testStoredLanguageRoundTrip() throws {
    let suiteName = "LocalizationTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }

    XCTAssertEqual(AppLanguage.stored(in: defaults), .system)

    for language in AppLanguage.allCases {
      AppLanguage.save(language, in: defaults)
      XCTAssertEqual(AppLanguage.stored(in: defaults), language)
    }

    defaults.set("kl", forKey: AppLanguage.defaultsKey)
    XCTAssertEqual(AppLanguage.stored(in: defaults), .system)
  }

  func testExplicitLanguageIgnoresSystemPreference() {
    XCTAssertEqual(AppLanguage.korean.resolved, .korean)
    XCTAssertEqual(AppLanguage.english.resolved, .english)
    XCTAssertEqual(AppLanguage.japanese.resolved, .japanese)
    XCTAssertEqual(
      AppLanguage.system.resolved,
      AppLanguage.systemPreferred()
    )
  }

  func testMenuTitlesAreDistinctAndNonEmpty() {
    let strings = EnglishStrings()
    let titles = AppLanguage.allCases.map { $0.menuTitle(using: strings) }
    XCTAssertEqual(Set(titles).count, AppLanguage.allCases.count)
    for title in titles {
      XCTAssertFalse(title.isEmpty)
    }
  }

  /// Every table has to fill in every string; a blank entry would ship as an
  /// invisible label rather than as a build failure.
  func testEveryLanguageTableIsComplete() {
    let tables: [(String, any AppStringsProviding)] = [
      ("Korean", KoreanStrings()),
      ("English", EnglishStrings()),
      ("Japanese", JapaneseStrings()),
    ]

    for (name, table) in tables {
      let mirror = Mirror(reflecting: table)
      XCTAssertGreaterThan(
        mirror.children.count,
        40,
        "\(name) table looks incomplete"
      )
      for child in mirror.children {
        let label = child.label ?? "<unnamed>"
        let value = try? XCTUnwrap(child.value as? String)
        XCTAssertFalse(
          (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty,
          "\(name).\(label) is empty"
        )
      }

      XCTAssertTrue(
        table.consentRecordNote(revision: "2026-07-27").contains("2026-07-27"),
        "\(name).consentRecordNote drops the revision"
      )
      let stepLabel = table.setupStepAccessibilityLabel(index: 3, title: "T")
      XCTAssertTrue(stepLabel.contains("3"), "\(name) step label drops index")
      XCTAssertTrue(stepLabel.contains("T"), "\(name) step label drops title")
      let failure = table.coreAudioFailure(
        operation: table.operationCreateTap,
        code: "'who?'",
        status: -4
      )
      XCTAssertTrue(failure.contains(table.operationCreateTap))
      XCTAssertTrue(failure.contains("'who?'"))
      XCTAssertTrue(failure.contains("-4"))
    }
  }

  func testActiveStringTableFollowsSelectedLanguage() {
    let original = AppLanguage.stored()
    defer { L.update(to: original) }

    L.update(to: .japanese)
    XCTAssertEqual(L.s.okButton, JapaneseStrings().okButton)
    XCTAssertEqual(L.s.errorInvalidTap, JapaneseStrings().errorInvalidTap)

    L.update(to: .korean)
    XCTAssertEqual(L.s.errorInvalidTap, KoreanStrings().errorInvalidTap)
  }
}
