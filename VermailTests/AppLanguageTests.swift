import Foundation
import Testing
@testable import Vermail

struct AppLanguageTests {
    private let suiteName = "AppLanguageTests.\(UUID().uuidString)"

    @Test func availableLanguagesComeFromBundle() {
        let codes = AppLanguage.available().compactMap(\.code)
        #expect(Set(codes) == Set(Bundle.main.localizations).subtracting(["Base"]))
        #expect(codes.contains("ru"))
    }

    @Test(arguments: [("en", "English"), ("ru", "Русский"), ("de", "Deutsch")])
    func nativeName(code: String, expected: String) {
        #expect(AppLanguage(code: code).nativeName == expected)
    }

    @Test func applyAndReadBack() throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let available = [AppLanguage(code: "en"), AppLanguage(code: "ru")]

        #expect(AppLanguage.current(in: defaults, bundleIdentifier: suiteName, available: available) == .system)

        AppLanguage(code: "ru").apply(to: defaults)
        #expect(defaults.stringArray(forKey: AppLanguage.appleLanguagesKey) == ["ru"])
        #expect(AppLanguage.current(in: defaults, bundleIdentifier: suiteName, available: available).code == "ru")

        AppLanguage.system.apply(to: defaults)
        #expect(AppLanguage.current(in: defaults, bundleIdentifier: suiteName, available: available) == .system)
    }

    @Test func resolvedCodeFollowsTheSelectionOrTheSystemList() {
        let available = ["en", "ru"]
        #expect(AppLanguage(code: "ru").resolvedCode(availableCodes: available, systemLanguages: ["en"]) == "ru")
        #expect(AppLanguage.system.resolvedCode(availableCodes: available, systemLanguages: ["ru-RU", "en"]) == "ru")
        #expect(AppLanguage.system.resolvedCode(availableCodes: available, systemLanguages: ["en"]) == "en")
    }

    @Test func removedLanguageFallsBackToSystem() throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        AppLanguage(code: "de").apply(to: defaults)
        let current = AppLanguage.current(
            in: defaults,
            bundleIdentifier: suiteName,
            available: [AppLanguage(code: "en")]
        )
        #expect(current == .system)
    }
}
