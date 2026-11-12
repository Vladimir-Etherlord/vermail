import CryptoKit
import Foundation
import MailCore
import MailTransport

public enum POP3 {
    public static let defaultPort = 110
    public static let defaultSecurePort = 995

    public static func defaultPort(for security: ConnectionSecurity) -> Int {
        security == .ssl ? defaultSecurePort : defaultPort
    }
}

public enum POP3AuthenticationMethod: Sendable {
    case userPass
    case apop
    case plain
    case login
    case cramMD5
    case xoauth2
}

public struct POP3Credentials: Sendable {
    public var username: String
    public var password: String?
    public var oauthBearerToken: String?

    public init(username: String, password: String? = nil, oauthBearerToken: String? = nil) {
        self.username = username
        self.password = password
        self.oauthBearerToken = oauthBearerToken
    }
}

public enum POP3Error: Error, Equatable, Sendable {
    case invalidGreeting(String)
    case invalidResponse(String)
    case serverError(String)
    case authenticationFailed(String)
    case missingPassword
    case missingOAuthToken
    case missingAPOPChallenge
    case messageNotFound(String)
}

public actor POP3Client: MailFetching {
    private let connection: any MailConnection
    private let useStartTLS: Bool
    private var isConnected = false
    private var didUpgradeToTLS = false
    private var challenge: String?
    private var isAuthenticated = false

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
        let line = try await readStatusLine()
        guard line.ok else {
            throw POP3Error.invalidGreeting(line.text)
        }
        challenge = extractChallenge(fromGreeting: line.text)
        isConnected = true

        if useStartTLS, !didUpgradeToTLS {
            _ = try await sendSingleLineCommand("STLS")
            try await connection.startTLS()
            didUpgradeToTLS = true
        }
    }

    public func authenticate(
        credentials: POP3Credentials,
        method: POP3AuthenticationMethod = .userPass
    ) async throws {
        try await connect()
        switch method {
        case .userPass:
            try await authenticateUserPass(credentials: credentials)
        case .apop:
            try await authenticateAPOP(credentials: credentials)
        case .plain:
            try await authenticatePlain(credentials: credentials)
        case .login:
            try await authenticateLogin(credentials: credentials)
        case .cramMD5:
            try await authenticateCRAMMD5(credentials: credentials)
        case .xoauth2:
            try await authenticateXOAUTH2(credentials: credentials)
        }
        isAuthenticated = true
    }

    public func capabilities() async throws -> [String] {
        try await connect()
        let lines = try await sendMultilineCommand("CAPA")
        return lines.map { $0.uppercased() }
    }

    public func listMessages() async throws -> [RemoteMessageRef] {
        try await ensureAuthenticated()
        let uidByIndex = try await uidByIndex()
        let sizeByIndex = try await sizeByIndex()
        return uidByIndex.compactMap { index, uid in
            guard let size = sizeByIndex[index] else { return nil }
            return RemoteMessageRef(uid: uid, size: size)
        }
        .sorted { $0.uid < $1.uid }
    }

    public func fetchMessage(_ ref: RemoteMessageRef) async throws -> Data {
        try await ensureAuthenticated()
        let index = try await messageIndex(forUID: ref.uid)
        let lines = try await sendMultilineCommand("RETR \(index)", dotUnstuff: true)
        var data = Data()
        for line in lines {
            data.append(Data(line.utf8))
            data.append(Data("\r\n".utf8))
        }
        return data
    }

    public func deleteMessages(_ refs: [RemoteMessageRef]) async throws {
        try await ensureAuthenticated()
        if refs.isEmpty {
            return
        }
        let uidToIndex = try await uidByIndex().reduce(into: [String: Int]()) { result, pair in
            result[pair.value] = pair.key
        }
        for ref in refs {
            guard let index = uidToIndex[ref.uid] else {
                throw POP3Error.messageNotFound(ref.uid)
            }
            _ = try await sendSingleLineCommand("DELE \(index)")
        }
    }

    public func close() async {
        if isConnected {
            _ = try? await sendSingleLineCommand("QUIT")
        }
        await connection.close()
        isConnected = false
        isAuthenticated = false
    }
}

private extension POP3Client {
    func ensureAuthenticated() async throws {
        try await connect()
        if !isAuthenticated {
            throw POP3Error.authenticationFailed("Not authenticated")
        }
    }

    func authenticateUserPass(credentials: POP3Credentials) async throws {
        guard let password = credentials.password else { throw POP3Error.missingPassword }
        _ = try await sendSingleLineCommand("USER \(credentials.username)")
        _ = try await sendSingleLineCommand("PASS \(password)", sensitive: true)
    }

    func authenticateAPOP(credentials: POP3Credentials) async throws {
        guard let password = credentials.password else { throw POP3Error.missingPassword }
        guard let challenge else { throw POP3Error.missingAPOPChallenge }
        let digest = Insecure.MD5.hash(data: Data((challenge + password).utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        _ = try await sendSingleLineCommand("APOP \(credentials.username) \(digest)", sensitive: true)
    }

    func authenticatePlain(credentials: POP3Credentials) async throws {
        guard let password = credentials.password else { throw POP3Error.missingPassword }
        let payload = Data("\u{0}\(credentials.username)\u{0}\(password)".utf8).base64EncodedString()
        _ = try await sendSingleLineCommand("AUTH PLAIN \(payload)", sensitive: true)
    }

    func authenticateLogin(credentials: POP3Credentials) async throws {
        guard let password = credentials.password else { throw POP3Error.missingPassword }
        try await connection.writeLine("AUTH LOGIN")
        _ = try await readAuthChallengeLine()
        try await connection.writeLine(Data(credentials.username.utf8).base64EncodedString(), sensitive: true)
        _ = try await readAuthChallengeLine()
        _ = try await sendSingleLineCommand(Data(password.utf8).base64EncodedString(), sensitive: true)
    }

    func authenticateCRAMMD5(credentials: POP3Credentials) async throws {
        guard let password = credentials.password else { throw POP3Error.missingPassword }
        try await connection.writeLine("AUTH CRAM-MD5")
        let challengeLine = try await readAuthChallengeLine()
        let b64 = challengeLine.dropFirst(2)
        guard let challengeData = Data(base64Encoded: String(b64)) else {
            throw POP3Error.invalidResponse(challengeLine)
        }
        let key = SymmetricKey(data: Data(password.utf8))
        let digest = HMAC<Insecure.MD5>.authenticationCode(for: challengeData, using: key)
            .map { String(format: "%02x", $0) }
            .joined()
        let response = "\(credentials.username) \(digest)"
        _ = try await sendSingleLineCommand(Data(response.utf8).base64EncodedString(), sensitive: true)
    }

    func authenticateXOAUTH2(credentials: POP3Credentials) async throws {
        guard let token = credentials.oauthBearerToken else { throw POP3Error.missingOAuthToken }
        let payload = "user=\(credentials.username)\u{1}auth=Bearer \(token)\u{1}\u{1}"
        _ = try await sendSingleLineCommand("AUTH XOAUTH2 \(Data(payload.utf8).base64EncodedString())", sensitive: true)
    }

    func uidByIndex() async throws -> [Int: String] {
        let lines = try await sendMultilineCommand("UIDL")
        var result: [Int: String] = [:]
        for line in lines {
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2, let index = Int(parts[0]) else {
                throw POP3Error.invalidResponse(line)
            }
            result[index] = parts[1]
        }
        return result
    }

    func sizeByIndex() async throws -> [Int: Int] {
        let lines = try await sendMultilineCommand("LIST")
        var result: [Int: Int] = [:]
        for line in lines {
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2, let index = Int(parts[0]), let size = Int(parts[1]) else {
                throw POP3Error.invalidResponse(line)
            }
            result[index] = size
        }
        return result
    }

    func messageIndex(forUID uid: String) async throws -> Int {
        let uidByIndex = try await uidByIndex()
        guard let pair = uidByIndex.first(where: { $0.value == uid }) else {
            throw POP3Error.messageNotFound(uid)
        }
        return pair.key
    }

    func sendSingleLineCommand(_ command: String, sensitive: Bool = false) async throws -> String {
        try await connection.writeLine(command, sensitive: sensitive)
        let line = try await readStatusLine()
        if line.ok {
            return line.text
        }
        throw POP3Error.serverError(line.text)
    }

    func sendMultilineCommand(_ command: String, dotUnstuff: Bool = false) async throws -> [String] {
        _ = try await sendSingleLineCommand(command)
        var lines: [String] = []
        while true {
            let next = try await connection.readLineString()
            if next == "." {
                break
            }
            if dotUnstuff, next.hasPrefix("..") {
                lines.append(String(next.dropFirst()))
            } else {
                lines.append(next)
            }
        }
        return lines
    }

    func readStatusLine() async throws -> (ok: Bool, text: String) {
        let line = try await connection.readLineString()
        if line.hasPrefix("+OK") {
            return (true, line)
        }
        if line.hasPrefix("-ERR") {
            return (false, line)
        }
        throw POP3Error.invalidResponse(line)
    }

    func readAuthChallengeLine() async throws -> String {
        let line = try await connection.readLineString()
        if line.hasPrefix("+ ") {
            return line
        }
        if line.hasPrefix("-ERR") {
            throw POP3Error.authenticationFailed(line)
        }
        throw POP3Error.invalidResponse(line)
    }

    func extractChallenge(fromGreeting greeting: String) -> String? {
        guard let start = greeting.firstIndex(of: "<"),
              let end = greeting[start...].firstIndex(of: ">")
        else {
            return nil
        }
        return String(greeting[start ... end])
    }
}
