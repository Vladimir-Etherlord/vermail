import Foundation
import MailCore
import MailStorage
import MIMEKit
import SMTPKit
import Testing
@testable import Vermail

struct ComposeBuilderTests {
    @Test func replyAndReplyAllSkipOwnAddresses() {
        let accountID = UUID()
        let identity = MailIdentity(
            accountID: accountID,
            displayName: "Me",
            emailAddress: "me@example.com"
        )
        let original = ComposeOriginal(
            accountID: accountID,
            from: "Alice <alice@example.com>",
            to: ["Me <me@example.com>", "Bob <bob@example.com>"],
            cc: ["carol@example.com", "alice@example.com"],
            bcc: [],
            subject: "Re: Hello",
            body: "Original text",
            date: nil,
            attachments: [],
            existingMessageID: nil,
            remoteUID: nil
        )

        let reply = ComposeMessageBuilder.reply(to: original, identity: identity)
        #expect(reply.to == ["Alice <alice@example.com>"])
        #expect(reply.subject == "Re: Hello")
        #expect(reply.body.contains("> Original text"))

        let replyAll = ComposeMessageBuilder.replyAll(
            to: original,
            identity: identity,
            ownAddresses: ["me@example.com"]
        )
        #expect(replyAll.cc == ["Bob <bob@example.com>", "carol@example.com"])
    }

    @Test func forwardKeepsAttachmentsAndPrefixesSubject() {
        let identity = MailIdentity(accountID: UUID(), displayName: "Me", emailAddress: "me@example.com")
        let attachment = ComposeAttachment(filename: "notes.txt", mimeType: "text/plain", data: Data("abc".utf8))
        let original = ComposeOriginal(
            accountID: identity.accountID,
            from: "alice@example.com",
            to: ["me@example.com"],
            cc: [],
            bcc: [],
            subject: "Notes",
            body: "See file",
            date: nil,
            attachments: [attachment],
            existingMessageID: nil,
            remoteUID: nil
        )

        let draft = ComposeMessageBuilder.forward(original: original, identity: identity)
        #expect(draft.subject == "Fwd: Notes")
        #expect(draft.attachments == [attachment])
        #expect(draft.body.contains("See file"))
    }

    @Test func smtpEnvelopeHidesBccWhileLocalCopyKeepsIt() throws {
        let identity = MailIdentity(accountID: UUID(), displayName: "Me", emailAddress: "me@example.com")
        let draft = ComposeDraft(
            accountID: identity.accountID,
            identityID: identity.id,
            to: ["bob@example.com"],
            bcc: ["secret@example.com"],
            subject: "Hello",
            body: "Body"
        )

        let smtp = try #require(
            ComposeMessageBuilder.smtpMessage(draft: draft, identity: identity, signature: "Best regards")
        )
        let smtpRaw = String(decoding: smtp.data, as: UTF8.self)
        #expect(smtp.recipients == ["bob@example.com", "secret@example.com"])
        #expect(smtp.from == "me@example.com")
        #expect(!smtpRaw.contains("Bcc:"))
        #expect(smtpRaw.contains("Best regards"))

        let stored = String(
            decoding: ComposeMessageBuilder.rawMessage(
                draft: draft,
                identity: identity,
                signature: "Best regards",
                includeBccHeader: true
            ),
            as: UTF8.self
        )
        #expect(stored.contains("Bcc: secret@example.com"))
    }
}

struct ComposeDeliveryTests {
    @Test func sendStoresMessageInSentAndSavesDrafts() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "ComposeDelivery-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let database = try MailDatabase(rootDirectory: root)
        let transport = RecordingTransport()
        let service = MailSendService(database: database, makeTransport: { _ in transport })
        let account = MailAccount(
            displayName: "Me",
            emailAddress: "me@example.com",
            incomingProtocol: .pop3,
            outgoingServer: OutgoingServerSettings(
                host: "smtp.example.com",
                port: 465,
                security: .ssl,
                authentication: .login
            )
        )
        let identity = MailIdentity(accountID: account.id, displayName: "Me", emailAddress: account.emailAddress)
        var draft = ComposeDraft(
            accountID: account.id,
            identityID: identity.id,
            to: ["bob@example.com"],
            bcc: ["secret@example.com"],
            subject: "Status",
            body: "All good"
        )

        let savedDraft = try await service.saveDraft(draft: draft, identity: identity, signature: "")
        draft.existingMessageID = savedDraft.id
        let drafts = try await database.messages(
            in: Mailbox(folder: .drafts, scope: .account(account.id)),
            accounts: [account]
        )
        #expect(drafts.map(\.id) == [savedDraft.id])

        let sent = try await service.send(draft: draft, account: account, identity: identity, signature: "Thanks")
        let sentMessages = try await database.messages(
            in: Mailbox(folder: .sent, scope: .account(account.id)),
            accounts: [account]
        )
        #expect(sentMessages.map(\.id) == [sent.id])
        #expect(sentMessages.first?.subject == "Status")
        let raw = try await String(decoding: database.rawMessageData(id: sent.id), as: UTF8.self)
        #expect(raw.contains("Bcc: secret@example.com"))
        #expect(raw.contains("Thanks"))

        let delivered = await transport.delivered()
        #expect(delivered.count == 1)
        #expect(delivered[0].recipients == ["bob@example.com", "secret@example.com"])
        #expect(!String(decoding: delivered[0].data, as: UTF8.self).contains("Bcc:"))
    }

    @Test func identityStoreCreatesDefaultIdentityAndAlias() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: "compose-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = ComposeIdentityStore(fileURL: fileURL)
        let account = MailAccount(displayName: "Work", emailAddress: "work@example.com", incomingProtocol: .pop3)
        let identities = try store.identities(for: [account])
        #expect(identities.count == 1)
        #expect(identities[0].emailAddress == "work@example.com")

        try store.setSignature("Best", for: account.id)
        #expect(try store.signature(for: account.id) == "Best")

        let alias = MailIdentity(accountID: account.id, displayName: "Alias", emailAddress: "alias@example.com")
        try store.addIdentity(alias)
        let updated = try store.identities(for: [account])
        #expect(updated.contains(alias))
    }
}

private actor RecordingTransport: OutgoingMailTransport {
    private var messages: [SMTPMessage] = []

    func send(_ message: SMTPMessage) async {
        messages.append(message)
    }

    func delivered() -> [SMTPMessage] {
        messages
    }
}
