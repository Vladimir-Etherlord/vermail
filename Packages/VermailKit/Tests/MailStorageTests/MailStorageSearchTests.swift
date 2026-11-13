import Foundation
import MailCore
import MailStorage
import Testing

struct MailStorageSearchTests {
    @Test func searchAcceptsCyrillicAndPunctuation() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let account = MailAccount(displayName: "Mail", emailAddress: "user@mail.ru", incomingProtocol: .pop3)
        _ = try await context.database.upsertMessage(.init(
            accountID: account.id,
            remoteUID: "ru-1",
            folder: .inbox,
            subject: "Привет",
            fromAddress: "анна@mail.ru",
            toAddresses: ["user@mail.ru"],
            snippet: "мир",
            receivedAt: Date(),
            rawSource: Data("Subject: Привет\r\n\r\nмир".utf8)
        ))

        let mailbox = Mailbox(folder: .inbox, scope: .account(account.id))
        let found = try await context.database.searchMessages(query: "Привет", in: mailbox, accounts: [account])
        #expect(found.map(\.remoteUID) == ["ru-1"])
        let punctuated = try await context.database.searchMessages(
            query: "\"Привет\"* (",
            in: mailbox,
            accounts: [account]
        )
        #expect(punctuated.map(\.remoteUID) == ["ru-1"])
        let empty = try await context.database.searchMessages(query: "\"", in: mailbox, accounts: [account])
        #expect(empty.isEmpty)
        #expect(MailDatabase.ftsMatchQuery("hello \"world") == "\"hello\"* \"world\"*")
    }

    @Test func storedPOP3RowsRememberWhenTheLocalCopyDisappears() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let account = MailAccount(displayName: "Mail", emailAddress: "user@mail.ru", incomingProtocol: .pop3)
        let saved = try await context.database.upsertMessage(.init(
            accountID: account.id,
            remoteUID: "uid-1",
            folder: .inbox,
            subject: "Hello",
            fromAddress: nil,
            toAddresses: [],
            snippet: nil,
            receivedAt: Date(),
            rawSource: Data("Hello".utf8)
        ))

        let present = try await context.database.pop3StoredMessages(
            accountID: account.id,
            remoteUIDs: ["uid-1", "other"]
        )
        #expect(present.map(\.remoteUID) == ["uid-1"])
        #expect(present[0].storedAt != nil)

        try await context.database.deleteMessages(ids: [saved.id])
        let removed = try await context.database.pop3StoredMessages(accountID: account.id, remoteUIDs: ["uid-1"])
        #expect(removed == [POP3StoredMessage(remoteUID: "uid-1", storedAt: nil)])
    }

    private func makeContext() throws -> (database: MailDatabase, root: URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "MailStorageSearchTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        return try (MailDatabase(rootDirectory: root), root)
    }
}
