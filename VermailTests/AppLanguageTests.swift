import Foundation
import Testing
@testable import Vermail

struct AppLanguageTests {
    private let suiteName = "AppLanguageTests.\(UUID().uuidString)"

    @Test func applyAndReadBack() throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(AppLanguage.current(in: defaults, bundleIdentifier: suiteName) == .system)

        AppLanguage.russian.apply(to: defaults)
        #expect(defaults.stringArray(forKey: AppLanguage.appleLanguagesKey) == ["ru"])
        #expect(AppLanguage.current(in: defaults, bundleIdentifier: suiteName) == .russian)

        AppLanguage.system.apply(to: defaults)
        #expect(AppLanguage.current(in: defaults, bundleIdentifier: suiteName) == .system)
    }
}
