import Foundation
import MailCore
import MailStorage
import Testing
@testable import Vermail

struct SyncEngineIMAPTests {
    @Test func foldersLandInMatchingMailboxesWithoutServerDeletion() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "MailSyncEngine-IMAPFolders-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try MailDatabase(rootDirectory: root)

        let account = MailAccount(
            displayName: "IMAP",
            emailAddress: "imap@example.com",
            incomingProtocol: .imap,
            details: AccountDetails(leaveMailOnServer: false)
        )
        let fetcher = FolderFetcher(boxes: [
            RemoteMailbox(name: "INBOX", folder: .inbox),
            RemoteMailbox(name: "Sent", folder: .sent),
        ])
        let engine = MailSyncEngine(
            database: database,
            secretStore: InMemorySecretStore(),
            fetcherFactory: FolderFetcherFactory(fetcher: fetcher)
        )

        _ = await engine.syncAccounts([account])
        let inbox = try await database.messages(in: Mailbox(folder: .inbox), accounts: [account])
        let sent = try await database.messages(in: Mailbox(folder: .sent), accounts: [account])
        #expect(inbox.map(\.subject) == ["inbox-1"])
        #expect(sent.map(\.subject) == ["sent-1"])
        #expect(await fetcher.deletedUIDs().isEmpty)
    }

    @Test func imapWritesReadMoveAndDeleteBackToTheServer() async throws {
        let context = try makeIMAPContext(boxes: [
            RemoteMailbox(name: "INBOX", folder: .inbox),
            RemoteMailbox(name: "Archive", folder: .archive),
            RemoteMailbox(name: "Trash", folder: .trash),
        ])
        defer { try? FileManager.default.removeItem(at: context.root) }
        let source = "INBOX\u{1}1\u{1}8"
        let stored = try await context.database.upsertMessage(sample(
            account: context.account,
            uid: source,
            folder: .inbox
        ))

        try await context.engine.setMessagesRead(true, ids: [stored.id], accounts: [context.account])
        #expect(await context.fetcher.readUIDs() == [source])

        try await context.engine.moveMessages(ids: [stored.id], to: .archive, accounts: [context.account])
        let archived = try await context.database.messages(in: Mailbox(folder: .archive), accounts: [context.account])
        #expect(archived.map(\.remoteUID) == ["next-\(source)"])
        #expect(await context.fetcher.movedFolders() == [.archive])

        try await context.engine.deleteMessages(ids: [stored.id], permanently: false, accounts: [context.account])
        #expect(await context.fetcher.movedFolders() == [.archive, .trash])

        let trashed = try await context.database.upsertMessage(
            sample(account: context.account, uid: "Trash\u{1}1\u{1}3", folder: .trash)
        )
        try await context.engine.deleteMessages(ids: [trashed.id], permanently: true, accounts: [context.account])
        #expect(await context.fetcher.deletedUIDs() == ["Trash\u{1}1\u{1}3"])
        let remaining = try await context.database.messages(in: Mailbox(folder: .trash), accounts: [context.account])
        #expect(remaining.map(\.id) == [stored.id])
    }

    @Test func imapMoveWithoutAServerMailboxLeavesTheMessageAlone() async throws {
        let context = try makeIMAPContext(boxes: [RemoteMailbox(name: "INBOX", folder: .inbox)])
        defer { try? FileManager.default.removeItem(at: context.root) }
        let stored = try await context.database.upsertMessage(
            sample(account: context.account, uid: "INBOX\u{1}1\u{1}8", folder: .inbox)
        )
        await #expect(throws: MailSyncEngineError.self) {
            try await context.engine.moveMessages(ids: [stored.id], to: .spam, accounts: [context.account])
        }
        let inbox = try await context.database.messages(in: Mailbox(folder: .inbox), accounts: [context.account])
        #expect(inbox.map(\.remoteUID) == ["INBOX\u{1}1\u{1}8"])
    }

    @Test func pop3ChangesDoNotOpenAConnection() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "MailSyncEngine-POP3Local-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try MailDatabase(rootDirectory: root)
        let account = MailAccount(displayName: "POP3", emailAddress: "pop@example.com", incomingProtocol: .pop3)
        let engine = MailSyncEngine(
            database: database,
            secretStore: InMemorySecretStore(),
            fetcherFactory: FailingFetcherFactory()
        )
        let stored = try await database.upsertMessage(sample(account: account, uid: "uid-1", folder: .inbox))
        try await engine.setMessagesRead(true, ids: [stored.id], accounts: [account])
        try await engine.deleteMessages(ids: [stored.id], permanently: false, accounts: [account])
        let trash = try await database.messages(in: Mailbox(folder: .trash), accounts: [account])
        #expect(trash.map(\.isRead) == [true])
    }

    private func sample(account: MailAccount, uid: String, folder: MailFolderKind) -> StoredMessageInput {
        StoredMessageInput(
            accountID: account.id,
            remoteUID: uid,
            folder: folder,
            subject: "letter",
            fromAddress: nil,
            toAddresses: [],
            snippet: nil,
            receivedAt: Date(),
            rawSource: Data("Subject: letter\r\n\r\n".utf8)
        )
    }

    private func makeIMAPContext(boxes: [RemoteMailbox]) throws -> IMAPWriteContext {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "MailSyncEngine-IMAPWrite-\(UUID().uuidString)", directoryHint: .isDirectory)
        let database = try MailDatabase(rootDirectory: root)
        let account = MailAccount(displayName: "IMAP", emailAddress: "imap@example.com", incomingProtocol: .imap)
        let fetcher = FolderFetcher(boxes: boxes)
        let engine = MailSyncEngine(
            database: database,
            secretStore: InMemorySecretStore(),
            fetcherFactory: FolderFetcherFactory(fetcher: fetcher)
        )
        return IMAPWriteContext(database: database, root: root, account: account, engine: engine, fetcher: fetcher)
    }
}

private struct IMAPWriteContext {
    var database: MailDatabase
    var root: URL
    var account: MailAccount
    var engine: MailSyncEngine
    var fetcher: FolderFetcher
}

private struct FailingFetcherFactory: MailFetcherFactory {
    func makeFetcher(
        for _: MailAccount,
        secretStore _: any AccountSecretStore
    ) async throws -> (fetcher: any MailFetching, cleanup: @Sendable () async -> Void) {
        throw MailSyncEngineError.server("POP3 must not connect")
    }
}

private struct FolderFetcherFactory: MailFetcherFactory {
    let fetcher: FolderFetcher

    func makeFetcher(
        for _: MailAccount,
        secretStore _: any AccountSecretStore
    ) async throws -> (fetcher: any MailFetching, cleanup: @Sendable () async -> Void) {
        (fetcher, {})
    }
}

private actor FolderFetcher: MailFetching {
    let boxes: [RemoteMailbox]
    private var selected: MailFolderKind = .inbox
    private var deletedRefs: [RemoteMessageRef] = []

    init(boxes: [RemoteMailbox]) {
        self.boxes = boxes
    }

    func remoteMailboxes() async throws -> [RemoteMailbox] {
        boxes
    }

    func selectMailbox(_ mailbox: RemoteMailbox) async throws {
        selected = mailbox.folder
    }

    func listMessages() async throws -> [RemoteMessageRef] {
        [RemoteMessageRef(uid: "\(selected.rawValue)-1", size: 12)]
    }

    func fetchMessage(_ ref: RemoteMessageRef) async throws -> Data {
        Data("Subject: \(ref.uid)\r\n\r\nBody".utf8)
    }

    func deleteMessages(_ refs: [RemoteMessageRef]) async throws {
        deletedRefs.append(contentsOf: refs)
    }

    func deletedUIDs() -> [String] {
        deletedRefs.map(\.uid)
    }

    private var readRefs: [RemoteMessageRef] = []
    private var moved: [(MailFolderKind, [String])] = []

    func setRead(_: Bool, refs: [RemoteMessageRef]) async throws {
        readRefs.append(contentsOf: refs)
    }

    func moveMessages(
        _ refs: [RemoteMessageRef],
        to mailbox: RemoteMailbox
    ) async throws -> [RemoteMessageMove] {
        moved.append((mailbox.folder, refs.map(\.uid)))
        return refs.map { RemoteMessageMove(sourceUID: $0.uid, destinationUID: "next-\($0.uid)") }
    }

    func readUIDs() -> [String] {
        readRefs.map(\.uid)
    }

    func movedFolders() -> [MailFolderKind] {
        moved.map(\.0)
    }
}
