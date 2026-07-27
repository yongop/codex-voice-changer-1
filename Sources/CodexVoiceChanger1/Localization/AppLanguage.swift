import Foundation

/// A language the app can actually render.
enum ResolvedLanguage: String, CaseIterable, Sendable {
  case korean = "ko"
  case english = "en"
  case japanese = "ja"

  /// Always written in its own script so the picker stays readable no matter
  /// which language the surrounding UI is in.
  var nativeName: String {
    switch self {
    case .korean:
      return "한국어"
    case .english:
      return "English"
    case .japanese:
      return "日本語"
    }
  }

  var strings: any AppStringsProviding {
    switch self {
    case .korean:
      return KoreanStrings()
    case .english:
      return EnglishStrings()
    case .japanese:
      return JapaneseStrings()
    }
  }
}

/// The user's display-language preference: either "follow macOS" or an
/// explicit override.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
  case system
  case korean = "ko"
  case english = "en"
  case japanese = "ja"

  static let defaultsKey = "appLanguage"

  var id: String { rawValue }

  var resolved: ResolvedLanguage {
    switch self {
    case .system:
      return AppLanguage.systemPreferred()
    case .korean:
      return .korean
    case .english:
      return .english
    case .japanese:
      return .japanese
    }
  }

  var strings: any AppStringsProviding { resolved.strings }

  func menuTitle(using strings: any AppStringsProviding) -> String {
    switch self {
    case .system:
      return
        "\(strings.languageSystemOption) (\(AppLanguage.systemPreferred().nativeName))"
    default:
      return resolved.nativeName
    }
  }

  /// The first supported language in the macOS preferred order, falling back
  /// to English for everyone else.
  static func systemPreferred(
    from preferredLanguages: [String] = Locale.preferredLanguages
  ) -> ResolvedLanguage {
    for identifier in preferredLanguages {
      guard
        let code = Locale(identifier: identifier).language.languageCode?
          .identifier,
        let match = ResolvedLanguage(rawValue: code)
      else {
        continue
      }
      return match
    }
    return .english
  }

  static func stored(
    in defaults: UserDefaults = .standard
  ) -> AppLanguage {
    guard let raw = defaults.string(forKey: defaultsKey),
      let language = AppLanguage(rawValue: raw)
    else {
      return .system
    }
    return language
  }

  static func save(
    _ language: AppLanguage,
    in defaults: UserDefaults = .standard
  ) {
    defaults.set(language.rawValue, forKey: defaultsKey)
  }
}
