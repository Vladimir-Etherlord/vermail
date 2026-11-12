import Foundation
import MailCore
import MailStorage
import MIMEKit
import Testing
@testable import Vermail

struct SyncEngineTests {
    @Test func accountStoreRoundtripsAccounts() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "AccountStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appending(path: "accounts.json")
        let store = AccountStore(fileURL: fileURL)

        #expect(try store.loadAccounts().isEmpty)

        let account = MailAccount(
            displayName: "Work",
            emailAddress: "work@example.com",
            incomingProtocol: .pop3,
            incomingServer: IncomingServerSettings(
                protocolKind: .pop3,
                host: "pop.example.com",
                port: 995,
                security: .ssl,
                authentication: .userPassword
            )
        )
        try store.saveAccounts([account])
        let loaded = try store.loadAccounts()
        #expect(loaded == [account])
    }

    @Test func metadataExtractorExtractsHeadersSnippetAndAttachments() {
        let raw = MIME.build(MIMEOutgoingMessage(
            from: "Alice <alice@example.com>",
            to: ["Bob <bob@example.com>", "carol@example.com"],
            subject: "Quarterly Update",
            plainBody: "Hello team,\r\nPlease see the attached report.",
            htmlBody: "<p>Hello team</p>",
            attachments: [
                MIMEAttachmentInput(filename: "report.pdf", mimeType: "application/pdf", data: Data("pdf".utf8)),
            ]
        ))

        let accountID = UUID()
        let input = MessageMetadataExtractor.makeStoredMessageInput(
            from: raw,
            accountID: accountID,
            remoteUID: "uid-42"
        )

        #expect(input.accountID == accountID)
        #expect(input.remoteUID == "uid-42")
        #expect(input.folder == .inbox)
        #expect(input.subject == "Quarterly Update")
        #expect(input.fromAddress == "Alice <alice@example.com>")
        #expect(input.toAddresses == ["Bob <bob@example.com>", "carol@example.com"])
        #expect(input.snippet == "Hello team, Please see the attached report.")
        #expect(input.hasAttachments)
    }

    @Test func metadataExtractorStripsHTMLWhenPlainBodyMissing() {
        let raw = Data(
            """
            From: news@example.com\r
            To: user@example.com\r
            Subject: Newsletter\r
            Date: Fri, 13 Nov 2026 10:15:00 +0300\r
            Content-Type: text/html; charset=utf-8\r
            \r
            <html><head><style>p { color: red; }</style></head>\
            <body><h1>Hello&nbsp;World</h1><p>Welcome!</p></body></html>
            """.utf8
        )

        let input = MessageMetadataExtractor.makeStoredMessageInput(
            from: raw,
            accountID: UUID(),
            remoteUID: "html-1"
        )

        #expect(input.snippet == "Hello World Welcome!")
        #expect(!input.hasAttachments)
        #expect(input.receivedAt != nil)
    }

    @Test func syncEngineDownloadsOnlyNewMessagesAndIsolatesErrors() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "MailSyncEngineTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let database = try MailDatabase(rootDirectory: root)
        let secretStore = InMemorySecretStore()

        let goodAccount = MailAccount(
            displayName: "Good",
            emailAddress: "good@example.com",
            incomingProtocol: .pop3
        )
        let failingAccount = MailAccount(
            displayName: "Bad",
            emailAddress: "bad@example.com",
            incomingProtocol: .pop3
        )

        _ = try await database.upsertMessage(StoredMessageInput(
            accountID: goodAccount.id,
            remoteUID: "existing-1",
            folder: .inbox,
            subject: "Existing",
            fromAddress: "old@example.com",
            toAddresses: ["good@example.com"],
            snippet: "Existing body",
            receivedAt: Date(),
            rawSource: Data("Subject: Existing\r\n\r\nExisting body".utf8)
        ))

        let newRaw = Data("From: sender@example.com\r\nTo: good@example.com\r\nSubject: New\r\n\r\nHello new".utf8)
        let factory = StubFetcherFactory(
            fetchers: [
                goodAccount.id: StubMailFetcher(
                    refs: [RemoteMessageRef(uid: "existing-1", size: 10), RemoteMessageRef(uid: "new-2", size: 20)],
                    payloads: ["new-2": newRaw]
                ),
            ],
            failingAccountIDs: [failingAccount.id]
        )

        let engine = MailSyncEngine(database: database, secretStore: secretStore, fetcherFactory: factory)
        let states = await engine.syncAccounts([goodAccount, failingAccount])

        #expect(states[goodAccount.id] == .idle)
        if case .error = states[failingAccount.id] {
            // Expected error for failing account while good account still succeeded.
        } else {
            Issue.record("Expected error state for failing account")
        }

        let stored = try await database.messages(
            in: Mailbox(folder: .inbox, scope: .account(goodAccount.id)),
            accounts: [goodAccount]
        )
        #expect(stored.count == 2)
        #expect(stored.contains(where: { $0.remoteUID == "new-2" && $0.subject == "New" }))
    }
}

private struct StubFetcherFactory: MailFetcherFactory {
    let fetchers: [UUID: StubMailFetcher]
    let failingAccountIDs: Set<UUID>

    func makeFetcher(
        for account: MailAccount,
        secretStore _: any AccountSecretStore
    ) async throws -> (fetcher: any MailFetching, cleanup: @Sendable () async -> Void) {
        if failingAccountIDs.contains(account.id) {
            throw MailSyncEngineError.missingCredentials
        }
        guard let fetcher = fetchers[account.id] else {
            throw MailSyncEngineError.missingIncomingServer
        }
        return (fetcher, {})
    }
}

private actor StubMailFetcher: MailFetching {
    let refs: [RemoteMessageRef]
    let payloads: [String: Data]

    init(refs: [RemoteMessageRef], payloads: [String: Data]) {
        self.refs = refs
        self.payloads = payloads
    }

    func listMessages() async throws -> [RemoteMessageRef] {
        refs
    }

    func fetchMessage(_ ref: RemoteMessageRef) async throws -> Data {
        payloads[ref.uid] ?? Data()
    }

    func deleteMessages(_: [RemoteMessageRef]) async throws {}
}
