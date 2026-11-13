import Foundation
import MailCore
import MailStorage
import Testing

struct MailStorageTests {
    @Test func rootDirectoryIsNamedAfterApp() throws {
        #expect(try MailStorage.defaultRootDirectory().lastPathComponent == "Vermail")
    }

    @Test func upsertListAndReadRawMessage() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.root) }

        let account = MailAccount(
            id: UUID(),
            displayName: "Mail.ru",
            emailAddress: "user@mail.ru",
            incomingProtocol: .pop3
        )

        let source = Data("Subject: test\r\n\r\nhello".utf8)
        _ = try await context.database.upsertMessage(.init(
            accountID: account.id,
            remoteUID: "uid-1",
            folder: .inbox,
            subject: "test",
            fromAddress: "alice@mail.ru",
            toAddresses: ["user@mail.ru"],
            snippet: "hello",
            receivedAt: Date(),
            rawSource: source
        ))

        let messages = try await context.database.messages(
            in: Mailbox(folder: .inbox, scope: .account(account.id)),
            accounts: [account]
        )
        #expect(messages.count == 1)
        #expect(messages[0].subject == "test")

        let raw = try await context.database.rawMessageData(id: messages[0].id)
        #expect(raw == source)
    }

    @Test func upsertByUIDUpdatesSingleRecord() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.root) }

        let account = MailAccount(
            id: UUID(),
            displayName: "A",
            emailAddress: "a@example.com",
            incomingProtocol: .pop3
        )

        _ = try await context.database.upsertMessage(.init(
            accountID: account.id,
            remoteUID: "same",
            folder: .inbox,
            subject: "one",
            fromAddress: nil,
            toAddresses: [],
            snippet: "first",
            receivedAt: Date(),
            rawSource: Data("first".utf8)
        ))
        _ = try await context.database.upsertMessage(.init(
            accountID: account.id,
            remoteUID: "same",
            folder: .inbox,
            subject: "two",
            fromAddress: nil,
            toAddresses: [],
            snippet: "second",
            receivedAt: Date(),
            rawSource: Data("second".utf8)
        ))

        let messages = try await context.database.messages(
            in: Mailbox(folder: .inbox, scope: .account(account.id)),
            accounts: [account]
        )
        #expect(messages.count == 1)
        #expect(messages[0].subject == "two")
    }

    @Test func unifiedMailboxRespectsIncludedAccounts() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.root) }

        let included = MailAccount(
            id: UUID(),
            displayName: "Included",
            emailAddress: "in@example.com",
            incomingProtocol: .pop3,
            isIncludedInUnifiedFolders: true
        )
        let hidden = MailAccount(
            id: UUID(),
            displayName: "Hidden",
            emailAddress: "hid@example.com",
            incomingProtocol: .imap,
            isIncludedInUnifiedFolders: false
        )

        _ = try await context.database.upsertMessage(.init(
            accountID: included.id,
            remoteUID: "uid-1",
            folder: .inbox,
            subject: "visible",
            fromAddress: nil,
            toAddresses: [],
            snippet: "visible",
            receivedAt: Date(),
            rawSource: Data("visible".utf8)
        ))
        _ = try await context.database.upsertMessage(.init(
            accountID: hidden.id,
            remoteUID: "uid-2",
            folder: .inbox,
            subject: "hidden",
            fromAddress: nil,
            toAddresses: [],
            snippet: "hidden",
            receivedAt: Date(),
            rawSource: Data("hidden".utf8)
        ))

        let unified = try await context.database.messages(in: Mailbox(folder: .inbox), accounts: [included, hidden])
        #expect(unified.count == 1)
        #expect(unified[0].subject == "visible")

        let hiddenOnly = try await context.database.messages(
            in: Mailbox(folder: .inbox, scope: .account(hidden.id)),
            accounts: [included, hidden]
        )
        #expect(hiddenOnly.count == 1)
        #expect(hiddenOnly[0].subject == "hidden")
    }

    @Test func ftsSearchFindsMessagesBySnippet() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.root) }

        let account = MailAccount(
            id: UUID(),
            displayName: "Search",
            emailAddress: "search@example.com",
            incomingProtocol: .pop3
        )

        _ = try await context.database.upsertMessage(.init(
            accountID: account.id,
            remoteUID: "a",
            folder: .inbox,
            subject: "Quarterly report",
            fromAddress: "boss@example.com",
            toAddresses: ["search@example.com"],
            snippet: "profit margin increased",
            receivedAt: Date(),
            rawSource: Data("a".utf8)
        ))
        _ = try await context.database.upsertMessage(.init(
            accountID: account.id,
            remoteUID: "b",
            folder: .inbox,
            subject: "Dinner",
            fromAddress: "friend@example.com",
            toAddresses: ["search@example.com"],
            snippet: "pizza tomorrow",
            receivedAt: Date(),
            rawSource: Data("b".utf8)
        ))

        let found = try await context.database.searchMessages(
            query: "profit",
            in: Mailbox(folder: .inbox),
            accounts: [account]
        )
        #expect(found.count == 1)
        #expect(found[0].subject == "Quarterly report")
    }

    @Test func pop3SyncPlanTracksUIDLs() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.root) }

        let account = MailAccount(
            id: UUID(),
            displayName: "Sync",
            emailAddress: "sync@example.com",
            incomingProtocol: .pop3
        )

        _ = try await context.database.upsertMessage(.init(
            accountID: account.id,
            remoteUID: "known",
            folder: .inbox,
            subject: "known",
            fromAddress: nil,
            toAddresses: [],
            snippet: nil,
            receivedAt: Date(),
            rawSource: Data("known".utf8)
        ))
        _ = try await context.database.upsertMessage(.init(
            accountID: account.id,
            remoteUID: "gone",
            folder: .inbox,
            subject: "gone",
            fromAddress: nil,
            toAddresses: [],
            snippet: nil,
            receivedAt: Date(),
            rawSource: Data("gone".utf8)
        ))

        let plan = try await context.database.pop3SyncPlan(
            accountID: account.id,
            serverRefs: [
                .init(uid: "known", size: 10),
                .init(uid: "new", size: 20),
            ]
        )

        #expect(plan.toDownload.map(\.uid) == ["new"])
        #expect(plan.alreadyKnown.map(\.uid) == ["known"])
        #expect(plan.missingOnServer == ["gone"])
    }

    @Test func relocateKeepsTheMessageAndUpdatesItsServerKey() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let account = MailAccount(displayName: "IMAP", emailAddress: "imap@example.com", incomingProtocol: .imap)
        let stored = try await context.database.upsertMessage(.init(
            accountID: account.id,
            remoteUID: "INBOX\u{1}1\u{1}8",
            folder: .inbox,
            subject: "moved",
            fromAddress: nil,
            toAddresses: [],
            snippet: nil,
            receivedAt: Date(),
            rawSource: Data("Subject: moved\r\n\r\n".utf8)
        ))
        try await context.database.relocateMessage(id: stored.id, remoteUID: "Trash\u{1}4\u{1}21", folder: .trash)
        let trash = try await context.database.messages(in: Mailbox(folder: .trash), accounts: [account])
        #expect(trash.map(\.remoteUID) == ["Trash\u{1}4\u{1}21"])
        let plan = try await context.database.pop3SyncPlan(
            accountID: account.id,
            serverRefs: [.init(uid: "Trash\u{1}4\u{1}21", size: 10)]
        )
        #expect(plan.toDownload.isEmpty)
        #expect(plan.alreadyKnown.map(\.uid) == ["Trash\u{1}4\u{1}21"])
    }

    private func makeContext() throws -> (database: MailDatabase, root: URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "MailStorageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let database = try MailDatabase(rootDirectory: root)
        return (database, root)
    }
}
