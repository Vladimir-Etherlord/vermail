import Foundation
import MailCore
import Testing
@testable import Vermail

struct LocalizationTests {
    @Test func appShipsEnglishAndRussian() {
        #expect(Set(Bundle.main.localizations).isSuperset(of: ["en", "ru"]))
    }

    @Test(arguments: [("Inbox", "Входящие"), ("Trash", "Корзина"), ("Language:", "Язык:")])
    func russianTranslation(key: String, expected: String) throws {
        let path = try #require(Bundle.main.path(forResource: "ru", ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        #expect(bundle.localizedString(forKey: key, value: nil, table: nil) == expected)
    }

    @Test func everyFolderHasRussianTitle() {
        let russian = Locale(identifier: "ru")
        for folder in MailFolderKind.allCases {
            var resource = folder.title
            resource.locale = russian
            #expect(String(localized: resource) != folder.title.key, "\(folder) is not translated")
        }
    }
}
