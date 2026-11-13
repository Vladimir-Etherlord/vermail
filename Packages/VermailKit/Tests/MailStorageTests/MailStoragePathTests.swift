import Foundation
import MailCore
import MailStorage
import Testing

struct MailStoragePathTests {
    @Test func databaseOpensWhenDirectoryNameContainsASpace() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "Application Support \(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "Vermail", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        _ = try MailDatabase(rootDirectory: root)
        let sqlite = root.appending(path: "storage.sqlite")
        #expect(FileManager.default.fileExists(atPath: sqlite.fileSystemPath))
        #expect(FileManager.default.fileExists(atPath: sqlite.path(percentEncoded: true)) == false)

        _ = try MailDatabase(rootDirectory: root)
    }
}
