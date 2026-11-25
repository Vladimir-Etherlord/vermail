import Foundation
import Testing
@testable import Vermail

struct SnippetPreviewTests {
    @Test func previewStopsBeforeZeroWidthPadding() {
        let html = "<p>Заберите до среды, 9 декабря, до 21:00</p>"
            + String(repeating: "&zwnj; ", count: 20)
            + "<p>Здравствуйте!</p>"
        let snippet = MessageMetadataExtractor.makeSnippet(plainBody: nil, htmlBody: html)
        #expect(snippet == "Заберите до среды, 9 декабря, до 21:00")
    }

    @Test func storedPreviewDropsEncodedPadding() {
        let stored = "Заберите до 21:00 &zwnj; &zwnj; &zwnj; &zwnj; &zwnj;"
        #expect(MessageMetadataExtractor.previewText(stored) == "Заберите до 21:00")
        let blanks = "Заберите до 21:00 " + String(repeating: "\u{2800}", count: 8) + " дальше"
        #expect(MessageMetadataExtractor.previewText(blanks) == "Заберите до 21:00")
    }

    @Test func previewDecodesASingleAmpersand() {
        #expect(MessageMetadataExtractor.previewText("A&amp;B") == "A&B")
        #expect(MessageMetadataExtractor.previewText("Hello&#8204;World") == "HelloWorld")
    }
}
