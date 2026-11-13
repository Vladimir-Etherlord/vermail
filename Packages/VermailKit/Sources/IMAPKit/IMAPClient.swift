import Foundation
import MailCore
import MailTransport

public enum IMAP {
    public static let defaultPort = 143
    public static let defaultSecurePort = 993

    public static func defaultPort(for security: ConnectionSecurity) -> Int {
        security == .ssl ? defaultSecurePort : defaultPort
    }
}

public enum IMAPAuthenticationMethod: Sendable {
    /// IMAP `LOGIN` command.
    case login
    case plain
    /// SASL `AUTHENTICATE LOGIN`.
    case saslLogin
    case cramMD5
    case xoauth2
}

public struct IMAPCredentials: Sendable, Equatable {
    public var username: String
    public var password: String?
    public var oauthBearerToken: String?

    public init(username: String, password: String? = nil, oauthBearerToken: String? = nil) {
        self.username = username
        self.password = password
        self.oauthBearerToken = oauthBearerToken
    }
}

public enum IMAPError: Error, Equatable, Sendable {
    case serverError(String)
    case invalidResponse(String)
    case missingPassword
    case missingOAuthToken
    case messageNotFound(String)
    case notAuthenticated
    case startTLSUnavailable
}

/// IMAP client. It downloads mailboxes that map onto `MailFolderKind` and writes
/// read state, moves, and deletions back to the server.
public actor IMAPClient: MailFetching {
    let connection: any MailConnection
    let useStartTLS: Bool
    var isConnected = false
    var isAuthenticated = false
    var didLoadCapabilities = false
    var capabilities: Set<String> = []
    var tagNumber = 0
    var selectedName: String?
    var uidValidity = "0"

    public init(connection: any MailConnection, useStartTLS: Bool = false) {
        self.connection = connection
        self.useStartTLS = useStartTLS
    }

    public init(configuration: TransportConfiguration, logger: TrafficLogger? = nil) {
        connection = StreamConnection(configuration: configuration, logger: logger)
        useStartTLS = configuration.security == .startTLS
    }

    public func connect() async throws {
        if isConnected {
            return
        }
        try await connection.open()
        let greeting = try await connection.readLineString()
        let upper = greeting.uppercased()
        guard upper.hasPrefix("* OK") || upper.hasPrefix("* PREAUTH") else {
            throw IMAPError.invalidResponse(greeting)
        }
        isConnected = true
        if upper.hasPrefix("* PREAUTH") {
            isAuthenticated = true
        }
        if useStartTLS {
            try await upgradeToTLS()
        }
    }

    public func allowUnauthenticatedAccess() async throws {
        try await connect()
        isAuthenticated = true
    }

    public func authenticate(
        credentials: IMAPCredentials,
        method: IMAPAuthenticationMethod = .login
    ) async throws {
        try await connect()
        if isAuthenticated {
            return
        }
        switch method {
        case .login:
            try await login(credentials)
        case .plain:
            try await authenticatePlain(credentials)
        case .saslLogin:
            try await authenticateSASLLogin(credentials)
        case .cramMD5:
            try await authenticateCRAMMD5(credentials)
        case .xoauth2:
            try await authenticateXOAUTH2(credentials)
        }
        isAuthenticated = true
    }

    public func remoteMailboxes() async throws -> [RemoteMailbox] {
        try await ensureAuthenticated()
        let reply = try await send("LIST \"\" \"*\"")
        return IMAPParser.mailboxes(from: reply.lines)
    }

    public func selectMailbox(_ mailbox: RemoteMailbox) async throws {
        try await ensureAuthenticated()
        try await select(rawName: mailbox.name)
    }

    public func listMessages() async throws -> [RemoteMessageRef] {
        try await ensureAuthenticated()
        if selectedName == nil {
            try await select(rawName: "INBOX")
        }
        let reply = try await send("UID FETCH 1:* (UID RFC822.SIZE FLAGS)")
        return messageRefs(from: reply)
    }

    public func fetchMessage(_ ref: RemoteMessageRef) async throws -> Data {
        try await ensureAuthenticated()
        guard let key = IMAPMessageKey.parse(ref.uid) else {
            throw IMAPError.messageNotFound(ref.uid)
        }
        try await select(rawName: key.mailbox)
        let reply = try await send("UID FETCH \(key.uid) (BODY.PEEK[])")
        guard let body = IMAPParser.fetchRecords(from: reply.lines).first(where: { $0.body != nil })?.body else {
            throw IMAPError.messageNotFound(ref.uid)
        }
        return body
    }

    public func deleteMessages(_ refs: [RemoteMessageRef]) async throws {
        if refs.isEmpty {
            return
        }
        try await ensureAuthenticated()
        try await loadCapabilities()
        let groups = Dictionary(grouping: refs) { ref in
            IMAPMessageKey.parse(ref.uid)?.mailbox ?? ""
        }
        for (mailbox, group) in groups {
            try await delete(group, mailbox: mailbox)
        }
    }

    public func close() async {
        await connection.close()
        isConnected = false
        isAuthenticated = false
        selectedName = nil
    }
}
