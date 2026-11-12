import CryptoKit
import Foundation
import MailTransport

public enum SMTP {
    public static let defaultPort = 25
    public static let defaultSubmissionPort = 587
    public static let defaultSecurePort = 465

    public static func defaultPort(for security: ConnectionSecurity) -> Int {
        switch security {
        case .none: defaultPort
        case .startTLS: defaultSubmissionPort
        case .ssl: defaultSecurePort
        }
    }
}

public enum SMTPAuthenticationMethod: Sendable {
    case plain
    case login
    case cramMD5
    case xoauth2
}

public struct SMTPCredentials: Sendable {
    public var username: String
    public var password: String?
    public var oauthBearerToken: String?

    public init(username: String, password: String? = nil, oauthBearerToken: String? = nil) {
        self.username = username
        self.password = password
        self.oauthBearerToken = oauthBearerToken
    }
}

public struct SMTPMessage: Sendable {
    public var from: String
    public var recipients: [String]
    public var data: Data

    public init(from: String, recipients: [String], data: Data) {
        self.from = from
        self.recipients = recipients
        self.data = data
    }
}

public enum SMTPError: Error, Equatable, Sendable {
    case invalidGreeting(String)
    case invalidResponse(String)
    case serverError(code: Int, message: String)
    case authenticationFailed(String)
    case missingPassword
    case missingOAuthToken
    case emptyRecipients
    case unsupportedAuthentication(String)
}

public actor SMTPClient {
    private let connection: any MailConnection
    private let useStartTLS: Bool
    private let ehloDomain: String
    private var isConnected = false
    private var didUpgradeToTLS = false
    private var capabilities: [String] = []

    public init(connection: any MailConnection, useStartTLS: Bool = false, ehloDomain: String = "vermail.local") {
        self.connection = connection
        self.useStartTLS = useStartTLS
        self.ehloDomain = ehloDomain
    }

    public init(
        configuration: TransportConfiguration,
        logger: TrafficLogger? = nil,
        ehloDomain: String = "vermail.local"
    ) {
        connection = StreamConnection(configuration: configuration, logger: logger)
        useStartTLS = configuration.security == .startTLS
        self.ehloDomain = ehloDomain
    }

    public func connect() async throws {
        if isConnected {
            return
        }
        try await connection.open()
        let greeting = try await readReply()
        guard greeting.code == 220 else {
            throw SMTPError.invalidGreeting(greeting.message)
        }
        isConnected = true

        capabilities = try await ehlo()

        if useStartTLS, !didUpgradeToTLS {
            guard capabilities.contains(where: { $0.uppercased().contains("STARTTLS") }) else {
                throw SMTPError.unsupportedAuthentication("STARTTLS")
            }
            _ = try await sendCommand("STARTTLS", expectedCodes: [220])
            try await connection.startTLS()
            didUpgradeToTLS = true
            capabilities = try await ehlo()
        }
    }

    public func serverCapabilities() async throws -> [String] {
        try await connect()
        return capabilities
    }

    public func authenticate(
        credentials: SMTPCredentials,
        method: SMTPAuthenticationMethod = .login
    ) async throws {
        try await connect()
        switch method {
        case .plain:
            try await authenticatePlain(credentials: credentials)
        case .login:
            try await authenticateLogin(credentials: credentials)
        case .cramMD5:
            try await authenticateCRAMMD5(credentials: credentials)
        case .xoauth2:
            try await authenticateXOAUTH2(credentials: credentials)
        }
    }

    public func send(_ message: SMTPMessage) async throws {
        try await connect()
        guard !message.recipients.isEmpty else {
            throw SMTPError.emptyRecipients
        }

        _ = try await sendCommand("MAIL FROM:<\(message.from)>", expectedCodes: [250])
        for recipient in message.recipients {
            _ = try await sendCommand("RCPT TO:<\(recipient)>", expectedCodes: [250, 251])
        }

        _ = try await sendCommand("DATA", expectedCodes: [354])
        let content = dotStuffed(message.data)
        try await connection.write(content, sensitive: false)
        try await connection.write(Data("\r\n.\r\n".utf8), sensitive: false)
        let completion = try await readReply()
        guard completion.code == 250 else {
            throw SMTPError.serverError(code: completion.code, message: completion.message)
        }
    }

    public func close() async {
        if isConnected {
            _ = try? await sendCommand("QUIT", expectedCodes: [221])
        }
        await connection.close()
        isConnected = false
        capabilities = []
    }
}

private extension SMTPClient {
    func authenticatePlain(credentials: SMTPCredentials) async throws {
        guard let password = credentials.password else { throw SMTPError.missingPassword }
        let payload = Data("\u{0}\(credentials.username)\u{0}\(password)".utf8).base64EncodedString()
        _ = try await sendCommand("AUTH PLAIN \(payload)", expectedCodes: [235], sensitive: true)
    }

    func authenticateLogin(credentials: SMTPCredentials) async throws {
        guard let password = credentials.password else { throw SMTPError.missingPassword }
        _ = try await sendCommand("AUTH LOGIN", expectedCodes: [334])
        _ = try await sendCommand(
            Data(credentials.username.utf8).base64EncodedString(),
            expectedCodes: [334],
            sensitive: true
        )
        _ = try await sendCommand(Data(password.utf8).base64EncodedString(), expectedCodes: [235], sensitive: true)
    }

    func authenticateCRAMMD5(credentials: SMTPCredentials) async throws {
        guard let password = credentials.password else { throw SMTPError.missingPassword }
        let challengeReply = try await sendCommand("AUTH CRAM-MD5", expectedCodes: [334])
        let b64Challenge = challengeReply.message.dropFirst(4)
        guard let challengeData = Data(base64Encoded: String(b64Challenge)) else {
            throw SMTPError.invalidResponse(challengeReply.message)
        }
        let key = SymmetricKey(data: Data(password.utf8))
        let digest = HMAC<Insecure.MD5>.authenticationCode(for: challengeData, using: key)
            .map { String(format: "%02x", $0) }
            .joined()
        let response = "\(credentials.username) \(digest)"
        _ = try await sendCommand(Data(response.utf8).base64EncodedString(), expectedCodes: [235], sensitive: true)
    }

    func authenticateXOAUTH2(credentials: SMTPCredentials) async throws {
        guard let token = credentials.oauthBearerToken else { throw SMTPError.missingOAuthToken }
        let payload = "user=\(credentials.username)\u{1}auth=Bearer \(token)\u{1}\u{1}"
        _ = try await sendCommand(
            "AUTH XOAUTH2 \(Data(payload.utf8).base64EncodedString())",
            expectedCodes: [235],
            sensitive: true
        )
    }

    func ehlo() async throws -> [String] {
        let reply = try await sendCommand("EHLO \(ehloDomain)", expectedCodes: [250], multiline: true)
        let lines = reply.lines
        if lines.count <= 1 {
            return []
        }
        return Array(lines.dropFirst())
    }

    func sendCommand(
        _ command: String,
        expectedCodes: Set<Int>,
        multiline: Bool = false,
        sensitive: Bool = false
    ) async throws -> SMTPReply {
        try await connection.writeLine(command, sensitive: sensitive)
        let reply = try await readReply(multiline: multiline)
        guard expectedCodes.contains(reply.code) else {
            if reply.code == 535 || reply.code == 534 {
                throw SMTPError.authenticationFailed(reply.message)
            }
            throw SMTPError.serverError(code: reply.code, message: reply.message)
        }
        return reply
    }

    func readReply(multiline: Bool = true) async throws -> SMTPReply {
        var lines: [String] = []
        while true {
            let line = try await connection.readLineString()
            lines.append(line)

            guard line.count >= 4, let code = Int(line.prefix(3)) else {
                throw SMTPError.invalidResponse(line)
            }

            if !multiline || line[line.index(line.startIndex, offsetBy: 3)] == " " {
                return SMTPReply(code: code, lines: lines)
            }
        }
    }

    func dotStuffed(_ data: Data) -> Data {
        let body = String(decoding: data, as: UTF8.self)
        var result: [String] = []
        let normalized = body.replacingOccurrences(of: "\r\n", with: "\n")
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(".") {
                result.append(".\(line)")
            } else {
                result.append(String(line))
            }
        }
        return Data(result.joined(separator: "\r\n").utf8)
    }
}

private struct SMTPReply: Sendable {
    let code: Int
    let lines: [String]

    var message: String {
        lines.last ?? ""
    }
}
