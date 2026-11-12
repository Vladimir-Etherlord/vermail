import MailStorage
import Testing

struct MailStorageTests {
    @Test func rootDirectoryIsNamedAfterApp() throws {
        #expect(try MailStorage.defaultRootDirectory().lastPathComponent == "Vermail")
    }
}
