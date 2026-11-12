import Foundation

public enum IncomingProtocol: String, CaseIterable, Codable, Sendable {
    case pop3
    case imap
}

public enum ServerSecurity: String, CaseIterable, Codable, Sendable {
    case none
    case ssl
    case startTLS
}

public enum ServerAuthenticationMethod: String, CaseIterable, Codable, Sendable {
    case none
    case userPassword
    case apop
    case plain
    case login
    case cramMD5
    case xoauth2
}

public struct IncomingServerSettings: Hashable, Codable, Sendable {
    public var protocolKind: IncomingProtocol
    public var host: String
    public var port: Int
    public var security: ServerSecurity
    public var authentication: ServerAuthenticationMethod

    public init(
        protocolKind: IncomingProtocol,
        host: String,
        port: Int,
        security: ServerSecurity,
        authentication: ServerAuthenticationMethod
    ) {
        self.protocolKind = protocolKind
        self.host = host
        self.port = port
        self.security = security
        self.authentication = authentication
    }
}

public struct OutgoingServerSettings: Hashable, Codable, Sendable {
    public var host: String
    public var port: Int
    public var security: ServerSecurity
    public var authentication: ServerAuthenticationMethod
    public var requiresAuthentication: Bool

    public init(
        host: String,
        port: Int,
        security: ServerSecurity,
        authentication: ServerAuthenticationMethod,
        requiresAuthentication: Bool = true
    ) {
        self.host = host
        self.port = port
        self.security = security
        self.authentication = authentication
        self.requiresAuthentication = requiresAuthentication
    }
}

public struct MailAccount: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var displayName: String
    public var emailAddress: String
    public var incomingProtocol: IncomingProtocol
    public var isIncludedInUnifiedFolders: Bool
    public var incomingServer: IncomingServerSettings?
    public var outgoingServer: OutgoingServerSettings?
    public var isEnabled: Bool
    public var details: AccountDetails?

    public init(
        id: UUID = UUID(),
        displayName: String,
        emailAddress: String,
        incomingProtocol: IncomingProtocol,
        isIncludedInUnifiedFolders: Bool = true,
        incomingServer: IncomingServerSettings? = nil,
        outgoingServer: OutgoingServerSettings? = nil,
        isEnabled: Bool = true,
        details: AccountDetails? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.emailAddress = emailAddress
        self.incomingProtocol = incomingProtocol
        self.isIncludedInUnifiedFolders = isIncludedInUnifiedFolders
        self.incomingServer = incomingServer
        self.outgoingServer = outgoingServer
        self.isEnabled = isEnabled
        self.details = details
    }

    public var incomingLogin: String {
        let custom = details?.incomingUsername.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? emailAddress : custom
    }

    public var outgoingLogin: String {
        let custom = details?.outgoingUsername.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? emailAddress : custom
    }

    public var allowsInvalidCertificates: Bool {
        details?.allowsInvalidCertificates ?? false
    }
}
