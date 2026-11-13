import Foundation
import MailCore
import MailStorage
import Testing

struct MailStorageOperationsTests {
    @Test func unreadFilterAndUnreadCounts() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.root) }

        let primary = MailAccount(
            displayName: "Primary",
            emailAddress: "primary@example.com",
            incomingProtocol: .pop3,
            isIncludedInUnifiedFolders: true
        )
        let secondary = MailAccount(
            displayName: "Secondary",
            emailAddress: "secondary@example.com",
            incomingProtocol: .pop3,
            isIncludedInUnifiedFolders: false
        )
        let accounts = [primary, secondary]

        let unreadInbox = try await insertSample(
            in: context.database,
            accountID: primary.id,
            uid: "u1",
            folder: .inbox,
            isRead: false
        )
        _ = try await insertSample(
            in: context.database,
            accountID: primary.id,
            uid: "u2",
            folder: .inbox,
            isRead: true
        )
        _ = try await insertSample(
            in: context.database,
            accountID: secondary.id,
            uid: "u3",
            folder: .trash,
            isRead: false
        )

        let unreadOnly = try await context.database.messages(
            in: Mailbox(folder: .inbox, scope: .unified),
            accounts: accounts,
            unreadOnly: true
        )
        #expect(unreadOnly.map(\.id) == [unreadInbox.id])

        let counts = try await context.database.unreadCounts(accounts: accounts)
        #expect(counts.count(for: Mailbox(folder: .inbox, scope: .unified)) == 1)
        #expect(counts.count(for: Mailbox(folder: .allMail, scope: .unified)) == 1)
        #expect(counts.count(for: Mailbox(folder: .trash, scope: .account(secondary.id))) == 1)
        #expect(counts.count(for: Mailbox(folder: .allMail, scope: .account(secondary.id))) == 0)
    }

    @Test func setReadMoveAndDeleteMessages() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.root) }

        let account = MailAccount(
            displayName: "Primary",
            emailAddress: "primary@example.com",
            incomingProtocol: .pop3
        )

        let first = try await insertSample(
            in: context.database,
            accountID: account.id,
            uid: "u1",
            folder: .inbox,
            isRead: false
        )
        let second = try await insertSample(
            in: context.database,
            accountID: account.id,
            uid: "u2",
            folder: .inbox,
            isRead: true
        )

        try await context.database.setRead(true, messageIDs: [first.id])
        try await context.database.setRead(false, messageIDs: [second.id])

        let unread = try await context.database.messages(
            in: Mailbox(folder: .inbox, scope: .unified),
            accounts: [account],
            unreadOnly: true
        )
        #expect(unread.map(\.id) == [second.id])

        try await context.database.moveMessages(ids: [second.id], to: .archive)
        let archived = try await context.database.messages(
            in: Mailbox(folder: .archive, scope: .unified),
            accounts: [account]
        )
        #expect(archived.map(\.id) == [second.id])

        let allMail = try await context.database.messages(
            in: Mailbox(folder: .allMail, scope: .unified),
            accounts: [account]
        )
        #expect(Set(allMail.map(\.id)) == [first.id, second.id])

        let rawPath = context.root.appending(path: first.rawFilePath)
        #expect(FileManager.default.fileExists(atPath: rawPath.fileSystemPath))
        try await context.database.deleteMessages(ids: [first.id])
        #expect(!FileManager.default.fileExists(atPath: rawPath.fileSystemPath))
    }

    @Test func recentAddressesAreUniqueAndRecentFirst() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.root) }

        let account = MailAccount(
            displayName: "Primary",
            emailAddress: "primary@example.com",
            incomingProtocol: .pop3
        )
        let olderDate = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try await insertSample(
            in: context.database,
            accountID: account.id,
            uid: "older",
            folder: .inbox,
            isRead: true,
            fromAddress: "older@example.com",
            toAddresses: ["primary@example.com"],
            receivedAt: olderDate
        )
        _ = try await insertSample(
            in: context.database,
            accountID: account.id,
            uid: "newer",
            folder: .inbox,
            isRead: true,
            fromAddress: "newer@example.com",
            toAddresses: ["primary@example.com", "older@example.com"],
            receivedAt: olderDate.addingTimeInterval(60)
        )

        let addresses = try await context.database.recentAddresses()
        #expect(addresses.first == "newer@example.com")
        #expect(addresses.contains("older@example.com"))
        #expect(addresses.filter { $0.caseInsensitiveCompare("older@example.com") == .orderedSame }.count == 1)
    }

    private func insertSample(
        in database: MailDatabase,
        accountID: UUID,
        uid: String,
        folder: MailFolderKind,
        isRead: Bool,
        fromAddress: String = "sender@example.com",
        toAddresses: [String] = ["user@example.com"],
        receivedAt: Date = .init()
    ) async throws -> StoredMessage {
        try await database.upsertMessage(.init(
            accountID: accountID,
            remoteUID: uid,
            folder: folder,
            subject: "Subject \(uid)",
            fromAddress: fromAddress,
            toAddresses: toAddresses,
            snippet: "Snippet \(uid)",
            receivedAt: receivedAt,
            isRead: isRead,
            rawSource: Data("Body \(uid)".utf8)
        ))
    }

    private func makeContext() throws -> (database: MailDatabase, root: URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "MailStorageOpsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let database = try MailDatabase(rootDirectory: root)
        return (database, root)
    }
}
