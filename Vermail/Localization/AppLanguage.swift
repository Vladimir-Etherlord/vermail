import Foundation

/// UI language override. The list of languages comes from the translations compiled into the app bundle,
/// so adding a language to `Localizable.xcstrings` is enough. macOS reads `AppleLanguages` only at launch,
/// so a change needs a restart.
struct AppLanguage: Hashable, Identifiable {
    /// `nil` means "follow the system language".
    let code: String?

    static let system = AppLanguage(code: nil)
    static let appleLanguagesKey = "AppleLanguages"

    var id: String {
        code ?? "system"
    }

    /// Language names are shown in their own language regardless of the current UI language.
    var nativeName: String? {
        code.map { code in
            let locale = Locale(identifier: code)
            return locale.localizedString(forIdentifier: code)?.capitalized(with: locale) ?? code
        }
    }

    static func available(in bundle: Bundle = .main) -> [AppLanguage] {
        bundle.localizations
            .filter { $0 != "Base" }
            .map(AppLanguage.init(code:))
            .sorted { ($0.nativeName ?? "").localizedStandardCompare($1.nativeName ?? "") == .orderedAscending }
    }

    /// Reads only the app's own domain: `UserDefaults.array(forKey:)` would fall back to the system language list.
    static func current(
        in defaults: UserDefaults = .standard,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        available: [AppLanguage] = available()
    ) -> AppLanguage {
        let domain = bundleIdentifier.flatMap { defaults.persistentDomain(forName: $0) }
        guard let code = (domain?[appleLanguagesKey] as? [String])?.first,
              available.contains(AppLanguage(code: code))
        else { return .system }
        return AppLanguage(code: code)
    }

    func apply(to defaults: UserDefaults = .standard) {
        if let code {
            defaults.set([code], forKey: Self.appleLanguagesKey)
        } else {
            defaults.removeObject(forKey: Self.appleLanguagesKey)
        }
    }
}
