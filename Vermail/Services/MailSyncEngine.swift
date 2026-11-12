import Foundation
import MailCore
import MailStorage
import MailTransport
import POP3Kit

enum AccountSyncState: Equatable, Sendable {
    case idle
    case syncing
    case error(String)
}

enum MailSyncEngineError: Error, LocalizedError, Equatable, Sendable {
    case missingIncomingServer
    case unsupportedProtocol(IncomingProtocol)
    case missingCredentials

    var errorDescription: String? {
        switch self {
        case .missingIncomingServer:
            String(localized: "Incoming server settings are missing.")
        case let .unsupportedProtocol(proto):
            String(localized: "Protocol \(proto.rawValue.uppercased()) is not supported yet.")
        case .missingCredentials:
            String(localized: "Missing account password or token.")
        }
    }
}

protocol MailFetcherFactory: Sendable {
    func makeFetcher(
        for account: MailAccount,
        secretStore: any AccountSecretStore
    ) async throws -> (fetcher: any MailFetching, cleanup: @Sendable () async -> Void)
}

struct DefaultMailFetcherFactory: MailFetcherFactory {
    func makeFetcher(
        for account: MailAccount,
        secretStore: any AccountSecretStore
    ) async throws -> (fetcher: any MailFetching, cleanup: @Sendable () async -> Void) {
        switch account.incomingProtocol {
        case .pop3:
            guard let server = account.incomingServer else {
                throw MailSyncEngineError.missingIncomingServer
            }
            let configuration = TransportConfiguration(
                host: server.host,
                port: server.port,
                security: connectionSecurity(from: server.security),
                allowsInvalidCertificates: account.allowsInvalidCertificates
            )
            let client = POP3Client(configuration: configuration)
            do {
                try await client.connect()
                if server.authentication != .none {
                    let credentials = try await pop3Credentials(
                        for: account,
                        method: server.authentication,
                        secretStore: secretStore
                    )
                    let method = pop3AuthMethod(from: server.authentication)
                    try await client.authenticate(credentials: credentials, method: method)
                }
                return (client, { await client.close() })
            } catch {
                await client.close()
                throw error
            }
        case .imap:
            throw MailSyncEngineError.unsupportedProtocol(.imap)
        }
    }

    private func pop3Credentials(
        for account: MailAccount,
        method: ServerAuthenticationMethod,
        secretStore: any AccountSecretStore
    ) async throws -> POP3Credentials {
        if method == .xoauth2 {
            guard let token = try await secretStore.readSecret(for: account.id, kind: .oauthAccessToken),
                  !token.isEmpty
            else {
                throw MailSyncEngineError.missingCredentials
            }
            return POP3Credentials(username: account.incomingLogin, oauthBearerToken: token)
        }

        guard let password = try await secretStore.readSecret(for: account.id, kind: .incomingPassword),
              !password.isEmpty
        else {
            throw MailSyncEngineError.missingCredentials
        }
        return POP3Credentials(username: account.incomingLogin, password: password)
    }

    private func connectionSecurity(from security: ServerSecurity) -> ConnectionSecurity {
        switch security {
        case .none: .none
        case .ssl: .ssl
        case .startTLS: .startTLS
        }
    }

    private func pop3AuthMethod(from method: ServerAuthenticationMethod) -> POP3AuthenticationMethod {
        switch method {
        case .none, .userPassword: .userPass
        case .apop: .apop
        case .plain: .plain
        case .login: .login
        case .cramMD5: .cramMD5
        case .xoauth2: .xoauth2
        }
    }
}

actor MailSyncEngine {
    private let database: MailDatabase
    private let secretStore: any AccountSecretStore
    private let fetcherFactory: any MailFetcherFactory

    init(
        database: MailDatabase,
        secretStore: any AccountSecretStore,
        fetcherFactory: any MailFetcherFactory = DefaultMailFetcherFactory()
    ) {
        self.database = database
        self.secretStore = secretStore
        self.fetcherFactory = fetcherFactory
    }

    func syncAccounts(_ accounts: [MailAccount]) async -> [UUID: AccountSyncState] {
        let enabledAccounts = accounts.filter(\.isEnabled)
        return await withTaskGroup(of: (UUID, AccountSyncState).self) { group in
            for account in enabledAccounts {
                group.addTask {
                    do {
                        try await self.syncAccount(account)
                        return (account.id, .idle)
                    } catch {
                        return (account.id, .error(error.localizedDescription))
                    }
                }
            }

            var results: [UUID: AccountSyncState] = [:]
            for await (id, state) in group {
                results[id] = state
            }
            return results
        }
    }

    func syncAccount(_ account: MailAccount) async throws {
        let (fetcher, cleanup) = try await fetcherFactory.makeFetcher(for: account, secretStore: secretStore)
        do {
            let refs = try await fetcher.listMessages()
            let plan = try await database.pop3SyncPlan(accountID: account.id, serverRefs: refs)
            for ref in plan.toDownload {
                let rawData = try await fetcher.fetchMessage(ref)
                let input = MessageMetadataExtractor.makeStoredMessageInput(
                    from: rawData,
                    accountID: account.id,
                    remoteUID: ref.uid,
                    folder: .inbox
                )
                _ = try await database.upsertMessage(input)
            }
            await cleanup()
        } catch {
            await cleanup()
            throw error
        }
    }
}
