import Foundation
import MailCore
import MailStorage
import MIMEKit
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class ComposeViewModel: Identifiable {
    nonisolated let sessionID: UUID

    private let database: MailDatabase
    private let sendService: MailSendService
    private let identityStore: ComposeIdentityStore

    var draft: ComposeDraft
    var accounts: [MailAccount]
    var identities: [MailIdentity]
    var signature: String
    var suggestions: [String] = []
    var toInput = ""
    var ccInput = ""
    var bccInput = ""
    var aliasName = ""
    var aliasEmail = ""
    var isSending = false
    var errorMessage: String?
    var statusMessage: String?

    nonisolated var id: UUID {
        sessionID
    }

    init(
        draft: ComposeDraft,
        accounts: [MailAccount],
        identities: [MailIdentity],
        signature: String,
        database: MailDatabase,
        sendService: MailSendService,
        identityStore: ComposeIdentityStore
    ) {
        sessionID = UUID()
        self.draft = draft
        self.accounts = accounts
        self.identities = identities
        self.signature = signature
        self.database = database
        self.sendService = sendService
        self.identityStore = identityStore
    }

    var selectedIdentityID: UUID {
        get { draft.identityID }
        set { selectIdentity(newValue) }
    }

    func loadSuggestions() async {
        suggestions = await (try? database.recentAddresses()) ?? []
    }

    func suggestions(matching query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return Array(suggestions.filter { $0.localizedCaseInsensitiveContains(trimmed) }.prefix(6))
    }

    func commitPendingInput() {
        draft.to.append(contentsOf: ComposeMessageBuilder.tokens(from: toInput))
        draft.cc.append(contentsOf: ComposeMessageBuilder.tokens(from: ccInput))
        draft.bcc.append(contentsOf: ComposeMessageBuilder.tokens(from: bccInput))
        toInput = ""
        ccInput = ""
        bccInput = ""
    }

    func selectIdentity(_ identityID: UUID) {
        guard let identity = identities.first(where: { $0.id == identityID }) else { return }
        draft.identityID = identity.id
        draft.accountID = identity.accountID
        signature = (try? identityStore.signature(for: identity.accountID)) ?? ""
    }

    func persistSignature() {
        try? identityStore.setSignature(signature, for: draft.accountID)
    }

    func addAlias() {
        let email = aliasEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.contains("@") else {
            errorMessage = String(localized: "Enter an email address for the alias.")
            return
        }
        let identity = MailIdentity(
            accountID: draft.accountID,
            displayName: aliasName.trimmingCharacters(in: .whitespacesAndNewlines),
            emailAddress: email
        )
        do {
            try identityStore.addIdentity(identity)
            identities.append(identity)
            selectIdentity(identity.id)
            aliasName = ""
            aliasEmail = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addAttachment(filename: String, data: Data) {
        let ext = (filename as NSString).pathExtension
        let mimeType = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        draft.attachments.append(ComposeAttachment(filename: filename, mimeType: mimeType, data: data))
    }

    func removeAttachment(id: UUID) {
        draft.attachments.removeAll { $0.id == id }
    }

    func send() async -> Bool {
        await perform { identity, _ in
            _ = try await self.sendService.send(
                draft: self.draft,
                account: self.account(for: identity),
                identity: identity,
                signature: self.signature
            )
        }
    }

    func saveDraft() async -> Bool {
        guard let identity = currentIdentity else {
            errorMessage = String(localized: "Choose a sender.")
            return false
        }
        commitPendingInput()
        isSending = true
        defer { isSending = false }
        do {
            let stored = try await sendService.saveDraft(
                draft: draft,
                identity: identity,
                signature: signature
            )
            draft.existingMessageID = stored.id
            statusMessage = String(localized: "Draft saved.")
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func perform(
        _ operation: (MailIdentity, MailAccount) async throws -> Void
    ) async -> Bool {
        guard let identity = currentIdentity else {
            errorMessage = String(localized: "Choose a sender.")
            return false
        }
        let account = account(for: identity)
        commitPendingInput()
        isSending = true
        defer { isSending = false }
        do {
            try await operation(identity, account)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private var currentIdentity: MailIdentity? {
        identities.first { $0.id == draft.identityID }
    }

    private func account(for identity: MailIdentity) -> MailAccount {
        accounts.first { $0.id == identity.accountID } ?? MailAccount(
            id: identity.accountID,
            displayName: identity.displayName,
            emailAddress: identity.emailAddress,
            incomingProtocol: .pop3
        )
    }
}
