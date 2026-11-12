import Foundation

/// UI language override. macOS reads `AppleLanguages` only at launch, so a change needs a restart.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case russian = "ru"

    static let appleLanguagesKey = "AppleLanguages"

    var id: String {
        rawValue
    }

    /// Language names are shown in their own language regardless of the current UI language.
    var nativeName: String? {
        switch self {
        case .system: nil
        case .english: "English"
        case .russian: "Русский"
        }
    }

    /// Reads only the app's own domain: `UserDefaults.array(forKey:)` would fall back to the system language list.
    static func current(
        in defaults: UserDefaults = .standard,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> AppLanguage {
        let domain = bundleIdentifier.flatMap { defaults.persistentDomain(forName: $0) }
        guard let codes = domain?[appleLanguagesKey] as? [String],
              let language = codes.first.flatMap(AppLanguage.init(rawValue:))
        else { return .system }
        return language
    }

    func apply(to defaults: UserDefaults = .standard) {
        if self == .system {
            defaults.removeObject(forKey: Self.appleLanguagesKey)
        } else {
            defaults.set([rawValue], forKey: Self.appleLanguagesKey)
        }
    }
}
