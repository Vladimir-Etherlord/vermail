import Foundation
import MailCore
import MailStorage
import MIMEKit
import Testing
@testable import Vermail

@MainActor
struct MainWindowViewModelTests {
    @Test func remoteImagePolicyExtractsEmailAndDetectsRemoteImages() throws {
        let suiteName = "RemoteImagePolicyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = RemoteImagePolicyStore(defaults: defaults)
        #expect(!store.isAlwaysAllowed(sender: "Newsletter <news@example.com>"))

        store.allowAlways(sender: "Newsletter <NEWS@example.com>")
        #expect(store.isAlwaysAllowed(sender: "news@example.com"))
        #expect(store.isAlwaysAllowed(sender: "Other Name <news@example.com>"))

        #expect(RemoteImagePolicyStore.containsRemoteImages(in: "<img src=\"https://cdn.example.com/a.png\">"))
        #expect(!RemoteImagePolicyStore.containsRemoteImages(in: "<p>No images here</p>"))
        #expect(!RemoteImagePolicyStore.containsRemoteImages(in: "<img src=\"cid:inline-1\">"))
    }

    @Test func selectMessageMarksReadAndLoadsParsedContent() async throws {
        let context = try makeContext()
        defer { context.cleanup() }

        let raw = MIME.build(MIMEOutgoingMessage(
            from: "Alice <alice@example.com>",
            to: ["user@example.com"],
            subject: "Hello",
            plainBody: "Plain text",
            htmlBody: "<p>Hello</p><img src=\"https://example.com/pixel.png\">"
        ))

        let saved = try await context.database.upsertMessage(
            MessageMetadataExtractor.makeStoredMessageInput(
                from: raw,
                accountID: context.account.id,
                remoteUID: "uid-1"
            )
        )

        await context.viewModel.loadInitialData()
        #expect(context.viewModel.messages.count == 1)
        #expect(context.viewModel.unreadCounts.count(for: Mailbox(folder: .inbox, scope: .unified)) == 1)

        await context.viewModel.selectMessage(saved.id)
        #expect(context.viewModel.selectedParsedMessage?.subject == "Hello")
        #expect(context.viewModel.shouldShowRemoteImageBanner)
        #expect(context.viewModel.unreadCounts.count(for: Mailbox(folder: .inbox, scope: .unified)) == 0)

        context.viewModel.allowRemoteImagesOnce()
        #expect(!context.viewModel.shouldShowRemoteImageBanner)
    }

    @Test func unreadFilterKeepsTheOpenMessageAfterItIsMarkedRead() async throws {
        let context = try makeContext()
        defer { context.cleanup() }

        let saved = try await context.database.upsertMessage(StoredMessageInput(
            accountID: context.account.id,
            remoteUID: "uid-unread",
            folder: .inbox,
            subject: "Unread",
            fromAddress: "sender@example.com",
            toAddresses: ["user@example.com"],
            snippet: "Body",
            receivedAt: Date(),
            isRead: false,
            rawSource: Data("Subject: Unread\r\n\r\nBody".utf8)
        ))

        await context.viewModel.loadInitialData()
        await context.viewModel.setShowUnreadOnly(true)
        await context.viewModel.selectMessage(saved.id)

        #expect(context.viewModel.messages.isEmpty)
        #expect(context.viewModel.selectedMessageID == saved.id)
        #expect(context.viewModel.selectedParsedMessage?.subject == "Unread")
    }

    @Test func deleteMovesToTrashThenDeletesPermanently() async throws {
        let context = try makeContext()
        defer { context.cleanup() }

        let saved = try await context.database.upsertMessage(StoredMessageInput(
            accountID: context.account.id,
            remoteUID: "uid-del",
            folder: .inbox,
            subject: "Delete me",
            fromAddress: "sender@example.com",
            toAddresses: ["user@example.com"],
            snippet: "Body",
            receivedAt: Date(),
            rawSource: Data("Subject: Delete me\r\n\r\nBody".utf8)
        ))

        await context.viewModel.loadInitialData()
        await context.viewModel.delete(ids: [saved.id])
        #expect(context.viewModel.messages.isEmpty)

        await context.viewModel.selectMailbox(Mailbox(folder: .trash, scope: .unified))
        #expect(context.viewModel.messages.map(\.id) == [saved.id])

        await context.viewModel.delete(ids: [saved.id])
        #expect(context.viewModel.messages.isEmpty)
    }

    @Test func deleteConfirmationKeepsTheIdsWhenTheAlertCloses() async throws {
        let context = try makeContext()
        defer { context.cleanup() }

        let saved = try await inboxMessage(in: context, uid: "uid-confirm", subject: "Confirm me")
        await context.viewModel.loadInitialData()
        context.viewModel.preferencesStore.preferences.confirmDelete = true

        context.viewModel.requestDelete([saved.id])
        #expect(context.viewModel.isDeleteConfirmationPresented)
        context.viewModel.isDeleteConfirmationPresented = false
        #expect(context.viewModel.pendingDeleteIDs == [saved.id])

        await context.viewModel.confirmPendingDelete()
        #expect(context.viewModel.messages.isEmpty)
        #expect(context.viewModel.pendingDeleteIDs.isEmpty)

        await context.viewModel.selectMailbox(Mailbox(folder: .trash, scope: .unified))
        #expect(context.viewModel.messages.map(\.id) == [saved.id])
    }

    @Test func markUnreadArchiveAndMoveStayWhereTheActionPutThem() async throws {
        let context = try makeContext()
        defer { context.cleanup() }

        let saved = try await inboxMessage(in: context, uid: "uid-actions", subject: "Actions")
        await context.viewModel.loadInitialData()

        await context.viewModel.selectMessage(saved.id)
        #expect(context.viewModel.messages.first?.isRead == true)

        await context.viewModel.toggleRead(ids: [saved.id])
        #expect(context.viewModel.messages.first?.isRead == false)
        await context.viewModel.selectMessage(saved.id)
        #expect(context.viewModel.messages.first?.isRead == false)

        await context.viewModel.move(ids: [saved.id], to: .archive)
        #expect(context.viewModel.messages.isEmpty)

        await context.viewModel.selectMailbox(Mailbox(folder: .archive, scope: .unified))
        #expect(context.viewModel.messages.map(\.id) == [saved.id])

        await context.viewModel.move(ids: [saved.id], to: .inbox)
        #expect(context.viewModel.messages.isEmpty)
        await context.viewModel.selectMailbox(Mailbox(folder: .inbox, scope: .unified))
        #expect(context.viewModel.messages.map(\.id) == [saved.id])
    }

    private func inboxMessage(in context: TestContext, uid: String, subject: String) async throws -> StoredMessage {
        try await context.database.upsertMessage(StoredMessageInput(
            accountID: context.account.id,
            remoteUID: uid,
            folder: .inbox,
            subject: subject,
            fromAddress: "sender@example.com",
            toAddresses: ["user@example.com"],
            snippet: "Body",
            receivedAt: Date(),
            rawSource: Data("Subject: \(subject)\r\n\r\nBody".utf8)
        ))
    }

    private struct TestContext {
        let database: MailDatabase
        let account: MailAccount
        let viewModel: MainWindowViewModel
        let cleanup: () -> Void
    }

    private func makeContext() throws -> TestContext {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "ViewModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let suiteName = "ViewModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))

        let database = try MailDatabase(rootDirectory: root)
        let account = MailAccount(
            displayName: "Main",
            emailAddress: "user@example.com",
            incomingProtocol: .pop3
        )
        let accountStore = AccountStore(fileURL: root.appending(path: "accounts.json"))
        try accountStore.saveAccounts([account])

        let engine = MailSyncEngine(database: database, secretStore: InMemorySecretStore())
        let imageStore = RemoteImagePolicyStore(defaults: defaults)
        let viewModel = MainWindowViewModel(
            database: database,
            accountStore: accountStore,
            syncEngine: engine,
            imagePolicyStore: imageStore
        )

        return TestContext(
            database: database,
            account: account,
            viewModel: viewModel,
            cleanup: {
                try? FileManager.default.removeItem(at: root)
                defaults.removePersistentDomain(forName: suiteName)
            }
        )
    }
}
