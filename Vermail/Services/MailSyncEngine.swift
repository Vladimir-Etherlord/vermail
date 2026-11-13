import Foundation
import IMAPKit
import MailCore
import MailStorage
import MailTransport
import POP3Kit

enum AccountSyncState: Equatable, Sendable {
    case idle
    case syncing
    case error(String)
}

struct IncomingMailNotice: Equatable, Sendable {
    var accountID: UUID
    var remoteUID: String
    var fromAddress: String?
    var subject: String?
    var snippet: String?
    /// False for the first download of an account, so a full mailbox does not notify all at once.
    var announcesArrival: Bool
}

struct MailSyncReport: Equatable, Sendable {
    var states: [UUID: AccountSyncState]
    var newMail: [IncomingMailNotice]
}

enum MailSyncEngineError: Error, LocalizedError, Equatable, Sendable {
    case missingIncomingServer
    case unsupportedProtocol(IncomingProtocol)
    case missingCredentials
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingIncomingServer:
            String(localized: "Incoming server settings are missing.")
        case let .unsupportedProtocol(proto):
            String(localized: "Protocol \(proto.rawValue.uppercased()) is not supported yet.")
        case .missingCredentials:
            String(localized: "Missing account password or token.")
        case let .server(message):
            message
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
            try await makePOP3Fetcher(for: account, secretStore: secretStore)
        case .imap:
            try await makeIMAPFetcher(for: account, secretStore: secretStore)
        }
    }

    private func makePOP3Fetcher(
        for account: MailAccount,
        secretStore: any AccountSecretStore
    ) async throws -> (fetcher: any MailFetching, cleanup: @Sendable () async -> Void) {
        guard let server = account.incomingServer else {
            throw MailSyncEngineError.missingIncomingServer
        }
        let client = POP3Client(configuration: transportConfiguration(for: server, account: account))
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
            throw MailSyncEngineError.presenting(error)
        }
    }

    private func makeIMAPFetcher(
        for account: MailAccount,
        secretStore: any AccountSecretStore
    ) async throws -> (fetcher: any MailFetching, cleanup: @Sendable () async -> Void) {
        guard let server = account.incomingServer else {
            throw MailSyncEngineError.missingIncomingServer
        }
        let client = IMAPClient(configuration: transportConfiguration(for: server, account: account))
        do {
            if server.authentication == .none {
                try await client.allowUnauthenticatedAccess()
            } else {
                let credentials = try await imapCredentials(
                    for: account,
                    method: server.authentication,
                    secretStore: secretStore
                )
                let method = imapAuth(from: server.authentication)
                try await client.authenticate(credentials: credentials, method: method)
            }
            return (client, { await client.close() })
        } catch {
            await client.close()
            throw MailSyncEngineError.presenting(error)
        }
    }

    private func transportConfiguration(
        for server: IncomingServerSettings,
        account: MailAccount
    ) -> TransportConfiguration {
        TransportConfiguration(
            host: server.host,
            port: server.port,
            security: connectionSecurity(from: server.security),
            allowsInvalidCertificates: account.allowsInvalidCertificates
        )
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

    private func imapCredentials(
        for account: MailAccount,
        method: ServerAuthenticationMethod,
        secretStore: any AccountSecretStore
    ) async throws -> IMAPCredentials {
        if method == .xoauth2 {
            guard let token = try await secretStore.readSecret(for: account.id, kind: .oauthAccessToken),
                  !token.isEmpty
            else {
                throw MailSyncEngineError.missingCredentials
            }
            return IMAPCredentials(username: account.incomingLogin, oauthBearerToken: token)
        }
        guard let password = try await secretStore.readSecret(for: account.id, kind: .incomingPassword),
              !password.isEmpty
        else {
            throw MailSyncEngineError.missingCredentials
        }
        return IMAPCredentials(username: account.incomingLogin, password: password)
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

    private func imapAuth(from method: ServerAuthenticationMethod) -> IMAPAuthenticationMethod {
        switch method {
        case .plain: .plain
        case .login: .saslLogin
        case .cramMD5: .cramMD5
        case .xoauth2: .xoauth2
        case .userPassword, .apop, .none: .login
        }
    }
}

actor MailSyncEngine {
    let database: MailDatabase
    let secretStore: any AccountSecretStore
    let fetcherFactory: any MailFetcherFactory

    init(
        database: MailDatabase,
        secretStore: any AccountSecretStore,
        fetcherFactory: any MailFetcherFactory = DefaultMailFetcherFactory()
    ) {
        self.database = database
        self.secretStore = secretStore
        self.fetcherFactory = fetcherFactory
    }

    func syncAccounts(_ accounts: [MailAccount]) async -> MailSyncReport {
        let enabledAccounts = accounts.filter(\.isEnabled)
        return await withTaskGroup(of: AccountSyncOutcome.self) { group in
            for account in enabledAccounts {
                group.addTask {
                    do {
                        let notices = try await self.syncAccount(account)
                        return AccountSyncOutcome(id: account.id, state: .idle, newMail: notices)
                    } catch {
                        return AccountSyncOutcome(
                            id: account.id,
                            state: .error(error.localizedDescription),
                            newMail: []
                        )
                    }
                }
            }

            var states: [UUID: AccountSyncState] = [:]
            var newMail: [IncomingMailNotice] = []
            for await outcome in group {
                states[outcome.id] = outcome.state
                newMail.append(contentsOf: outcome.newMail)
            }
            return MailSyncReport(states: states, newMail: newMail)
        }
    }

    func syncAccount(_ account: MailAccount) async throws -> [IncomingMailNotice] {
        let (fetcher, cleanup) = try await fetcherFactory.makeFetcher(for: account, secretStore: secretStore)
        do {
            let notices = try await downloadNewMail(account: account, fetcher: fetcher)
            await cleanup()
            return notices
        } catch {
            await cleanup()
            throw error
        }
    }

    private func downloadNewMail(
        account: MailAccount,
        fetcher: any MailFetching
    ) async throws -> [IncomingMailNotice] {
        let boxes = try await fetcher.remoteMailboxes()
        if boxes.isEmpty {
            return try await downloadInbox(account: account, fetcher: fetcher)
        }
        var notices: [IncomingMailNotice] = []
        for box in boxes {
            try await fetcher.selectMailbox(box)
            let refs = try await fetcher.listMessages()
            let stored = try await store(refs, account: account, fetcher: fetcher, folder: box.folder)
            notices.append(contentsOf: stored)
        }
        return notices
    }

    private func downloadInbox(
        account: MailAccount,
        fetcher: any MailFetching
    ) async throws -> [IncomingMailNotice] {
        let refs = try await fetcher.listMessages()
        let notices = try await store(refs, account: account, fetcher: fetcher, folder: .inbox)
        if account.incomingProtocol == .pop3 {
            try await applyServerRetention(account: account, fetcher: fetcher, serverRefs: refs)
        }
        return notices
    }

    private func store(
        _ refs: [RemoteMessageRef],
        account: MailAccount,
        fetcher: any MailFetching,
        folder: MailFolderKind
    ) async throws -> [IncomingMailNotice] {
        let plan = try await database.pop3SyncPlan(accountID: account.id, serverRefs: refs)
        let announces = folder == .inbox && (!plan.alreadyKnown.isEmpty || !plan.missingOnServer.isEmpty)
        var notices: [IncomingMailNotice] = []
        for ref in plan.toDownload {
            try await notices.append(storeOne(
                ref,
                account: account,
                fetcher: fetcher,
                folder: folder,
                announces: announces
            ))
        }
        return notices
    }

    private func storeOne(
        _ ref: RemoteMessageRef,
        account: MailAccount,
        fetcher: any MailFetching,
        folder: MailFolderKind,
        announces: Bool
    ) async throws -> IncomingMailNotice {
        let rawData = try await fetcher.fetchMessage(ref)
        var input = MessageMetadataExtractor.makeStoredMessageInput(
            from: rawData,
            accountID: account.id,
            remoteUID: ref.uid,
            folder: folder
        )
        if ref.isRead {
            input.isRead = true
        }
        _ = try await database.upsertMessage(input)
        return IncomingMailNotice(
            accountID: account.id,
            remoteUID: ref.uid,
            fromAddress: input.fromAddress,
            subject: input.subject,
            snippet: input.snippet,
            announcesArrival: announces
        )
    }

    private func applyServerRetention(
        account: MailAccount,
        fetcher: any MailFetching,
        serverRefs: [RemoteMessageRef]
    ) async throws {
        let details = account.details ?? AccountDetails()
        let removesCopies = !details.leaveMailOnServer
            || details.deleteFromServerAfterDays != nil
            || details.deleteFromServerWhenDeletedLocally
        guard removesCopies else { return }

        let stored = try await database.pop3StoredMessages(
            accountID: account.id,
            remoteUIDs: serverRefs.map(\.uid)
        )
        let doomed = POP3RetentionPlanner.messageRefsToRemove(
            serverRefs: serverRefs,
            stored: stored,
            policy: POP3RetentionPolicy(
                leaveMailOnServer: details.leaveMailOnServer,
                deleteFromServerAfterDays: details.deleteFromServerAfterDays,
                deleteWhenRemovedLocally: details.deleteFromServerWhenDeletedLocally
            ),
            now: Date()
        )
        if !doomed.isEmpty {
            try await fetcher.deleteMessages(doomed)
        }
    }
}

private struct AccountSyncOutcome: Sendable {
    var id: UUID
    var state: AccountSyncState
    var newMail: [IncomingMailNotice]
}
