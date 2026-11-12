import Foundation
import MailCore
import MailStorage
import MailTransport
import SMTPKit

protocol OutgoingMailTransport: Sendable {
    func send(_ message: SMTPMessage) async throws
}

enum MailSendError: Error, LocalizedError, Equatable {
    case missingOutgoingServer
    case missingCredentials
    case noRecipients

    var errorDescription: String? {
        switch self {
        case .missingOutgoingServer:
            String(localized: "Outgoing server settings are missing.")
        case .missingCredentials:
            String(localized: "Missing outgoing password or token.")
        case .noRecipients:
            String(localized: "Enter at least one recipient.")
        }
    }
}

struct SMTPOutgoingTransport: OutgoingMailTransport {
    let account: MailAccount
    let secretStore: any AccountSecretStore

    func send(_ message: SMTPMessage) async throws {
        guard let server = account.outgoingServer else {
            throw MailSendError.missingOutgoingServer
        }
        let client = SMTPClient(
            configuration: TransportConfiguration(
                host: server.host,
                port: server.port,
                security: connectionSecurity(server.security),
                allowsInvalidCertificates: account.allowsInvalidCertificates
            )
        )
        do {
            try await client.connect()
            if server.requiresAuthentication, server.authentication != .none {
                let credentials = try await credentials(for: server.authentication)
                try await client.authenticate(credentials: credentials, method: smtpMethod(server.authentication))
            }
            try await client.send(message)
            await client.close()
        } catch {
            await client.close()
            throw error
        }
    }

    private func credentials(for method: ServerAuthenticationMethod) async throws -> SMTPCredentials {
        if method == .xoauth2 {
            guard let token = try await secretStore.readSecret(for: account.id, kind: .oauthAccessToken),
                  !token.isEmpty
            else {
                throw MailSendError.missingCredentials
            }
            return SMTPCredentials(username: account.outgoingLogin, oauthBearerToken: token)
        }
        guard let password = try await secretStore.readSecret(for: account.id, kind: .outgoingPassword),
              !password.isEmpty
        else {
            throw MailSendError.missingCredentials
        }
        return SMTPCredentials(username: account.outgoingLogin, password: password)
    }

    private func connectionSecurity(_ security: ServerSecurity) -> ConnectionSecurity {
        switch security {
        case .none: .none
        case .ssl: .ssl
        case .startTLS: .startTLS
        }
    }

    private func smtpMethod(_ method: ServerAuthenticationMethod) -> SMTPAuthenticationMethod {
        switch method {
        case .plain: .plain
        case .cramMD5: .cramMD5
        case .xoauth2: .xoauth2
        case .login, .userPassword, .apop, .none: .login
        }
    }
}

struct MailSendService: Sendable {
    private let database: MailDatabase
    private let makeTransport: @Sendable (MailAccount) -> any OutgoingMailTransport

    init(database: MailDatabase, secretStore: any AccountSecretStore) {
        self.database = database
        makeTransport = { account in
            SMTPOutgoingTransport(account: account, secretStore: secretStore)
        }
    }

    init(
        database: MailDatabase,
        makeTransport: @escaping @Sendable (MailAccount) -> any OutgoingMailTransport
    ) {
        self.database = database
        self.makeTransport = makeTransport
    }

    func send(
        draft: ComposeDraft,
        account: MailAccount,
        identity: MailIdentity,
        signature: String
    ) async throws -> StoredMessage {
        guard let message = ComposeMessageBuilder.smtpMessage(
            draft: draft,
            identity: identity,
            signature: signature
        ) else {
            throw MailSendError.noRecipients
        }
        try await makeTransport(account).send(message)
        return try await store(
            draft: draft,
            identity: identity,
            signature: signature,
            folder: .sent
        )
    }

    func saveDraft(
        draft: ComposeDraft,
        identity: MailIdentity,
        signature: String
    ) async throws -> StoredMessage {
        try await store(draft: draft, identity: identity, signature: signature, folder: .drafts)
    }

    private func store(
        draft: ComposeDraft,
        identity: MailIdentity,
        signature: String,
        folder: MailFolderKind
    ) async throws -> StoredMessage {
        let raw = ComposeMessageBuilder.rawMessage(
            draft: draft,
            identity: identity,
            signature: signature,
            includeBccHeader: true
        )
        let body = ComposeMessageBuilder.composedBody(draft.body, signature: signature)
        return try await database.upsertMessage(
            StoredMessageInput(
                accountID: draft.accountID,
                remoteUID: draft.remoteUID,
                folder: folder,
                subject: draft.subject,
                fromAddress: ComposeMessageBuilder.formatAddress(
                    name: identity.displayName,
                    email: identity.emailAddress
                ),
                toAddresses: draft.to,
                snippet: MessageMetadataExtractor.makeSnippet(plainBody: body, htmlBody: nil),
                receivedAt: Date(),
                isRead: true,
                hasAttachments: !draft.attachments.isEmpty,
                rawSource: raw
            )
        )
    }
}
