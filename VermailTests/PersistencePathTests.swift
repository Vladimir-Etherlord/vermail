import Foundation
import MailCore
import MailStorage
import Testing
@testable import Vermail

struct PersistencePathTests {
    @Test func accountStoreRoundtripsWhenDirectoryNameContainsASpace() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "Application Support \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appending(path: "accounts.json")
        let account = MailAccount(
            displayName: "Work",
            emailAddress: "work@example.com",
            incomingProtocol: .pop3
        )
        try AccountStore(fileURL: fileURL).saveAccounts([account])

        let loaded = try AccountStore(fileURL: fileURL).loadAccounts()
        #expect(loaded == [account])
    }

    @Test func identityStoreReloadsWhenDirectoryNameContainsASpace() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "Application Support \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appending(path: "compose.json")
        let account = MailAccount(displayName: "Work", emailAddress: "work@example.com", incomingProtocol: .pop3)
        let store = ComposeIdentityStore(fileURL: fileURL)
        _ = try store.identities(for: [account])
        try store.setSignature("Best", for: account.id)

        let reloaded = ComposeIdentityStore(fileURL: fileURL)
        #expect(try reloaded.signature(for: account.id) == "Best")
        #expect(try reloaded.identities(for: [account]).count == 1)
    }

    @Test func fallbackMailboxIsAdoptedIntoADirectoryWhoseNameContainsASpace() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "Persistence \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let fallback = root.appending(path: "fallback", directoryHint: .isDirectory)
        let destination = root.appending(path: "Application Support", directoryHint: .isDirectory)
        _ = try MailDatabase(rootDirectory: fallback)
        let marker = fallback.appending(path: "raw/account-one", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: true)
        try Data("kept".utf8).write(to: marker.appending(path: "note.txt"))

        try StorageBootstrap.adoptFallbackMailbox(into: destination, fallbackRoot: fallback)

        let sqlite = destination.appending(path: "storage.sqlite")
        #expect(FileManager.default.fileExists(atPath: sqlite.fileSystemPath))
        let note = destination.appending(path: "raw/account-one/note.txt")
        #expect(try String(contentsOf: note, encoding: .utf8) == "kept")
        _ = try MailDatabase(rootDirectory: destination)
    }
}
