import Foundation
import MailCore
import MailTransport
import POP3Kit
import SMTPKit

enum AccountConnectionTester {
    static func testIncoming(_ draft: AccountDraft, storedSecret: String?) async throws {
        let account = draft.makeAccount()
        guard let server = account.incomingServer else {
            throw MailSyncEngineError.missingIncomingServer
        }
        let secret = resolvedSecret(typed: draft.incomingSecret, stored: storedSecret)
        let client = POP3Client(
            configuration: TransportConfiguration(
                host: server.host,
                port: server.port,
                security: connectionSecurity(server.security),
                allowsInvalidCertificates: account.allowsInvalidCertificates
            )
        )
        do {
            try await client.connect()
            if server.authentication != .none {
                let credentials = try credentials(account: account, method: server.authentication, secret: secret)
                try await client.authenticate(credentials: credentials, method: pop3Method(server.authentication))
            }
            await client.close()
        } catch {
            await client.close()
            throw error
        }
    }

    static func testOutgoing(_ draft: AccountDraft, storedSecret: String?) async throws {
        let account = draft.makeAccount()
        guard let server = account.outgoingServer else {
            throw MailSendError.missingOutgoingServer
        }
        let secret = resolvedSecret(typed: draft.outgoingSecret, stored: storedSecret)
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
                let credentials = try smtpCredentials(account: account, method: server.authentication, secret: secret)
                try await client.authenticate(credentials: credentials, method: smtpMethod(server.authentication))
            }
            await client.close()
        } catch {
            await client.close()
            throw error
        }
    }

    private static func resolvedSecret(typed: String, stored: String?) -> String {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (stored ?? "") : trimmed
    }

    private static func credentials(
        account: MailAccount,
        method: ServerAuthenticationMethod,
        secret: String
    ) throws -> POP3Credentials {
        if secret.isEmpty {
            throw MailSyncEngineError.missingCredentials
        }
        if method == .xoauth2 {
            return POP3Credentials(username: account.incomingLogin, oauthBearerToken: secret)
        }
        return POP3Credentials(username: account.incomingLogin, password: secret)
    }

    private static func smtpCredentials(
        account: MailAccount,
        method: ServerAuthenticationMethod,
        secret: String
    ) throws -> SMTPCredentials {
        if secret.isEmpty {
            throw MailSendError.missingCredentials
        }
        if method == .xoauth2 {
            return SMTPCredentials(username: account.outgoingLogin, oauthBearerToken: secret)
        }
        return SMTPCredentials(username: account.outgoingLogin, password: secret)
    }

    private static func connectionSecurity(_ security: ServerSecurity) -> ConnectionSecurity {
        switch security {
        case .none: .none
        case .ssl: .ssl
        case .startTLS: .startTLS
        }
    }

    private static func pop3Method(_ method: ServerAuthenticationMethod) -> POP3AuthenticationMethod {
        switch method {
        case .none, .userPassword: .userPass
        case .apop: .apop
        case .plain: .plain
        case .login: .login
        case .cramMD5: .cramMD5
        case .xoauth2: .xoauth2
        }
    }

    private static func smtpMethod(_ method: ServerAuthenticationMethod) -> SMTPAuthenticationMethod {
        switch method {
        case .plain: .plain
        case .cramMD5: .cramMD5
        case .xoauth2: .xoauth2
        case .login, .userPassword, .apop, .none: .login
        }
    }
}
