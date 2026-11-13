import Foundation
import Testing
@testable import MailCore

struct FileSystemPathTests {
    @Test func fileSystemPathKeepsSpaces() {
        let url = URL(fileURLWithPath: "/Users/example/Application Support/Vermail/accounts.json")
        #expect(url.fileSystemPath == "/Users/example/Application Support/Vermail/accounts.json")
        #expect(url.path(percentEncoded: true).contains("Application%20Support"))
    }
}
