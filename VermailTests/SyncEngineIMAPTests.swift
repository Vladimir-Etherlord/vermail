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
}
