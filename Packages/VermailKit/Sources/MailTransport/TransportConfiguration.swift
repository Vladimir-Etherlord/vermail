public enum ConnectionSecurity: String, CaseIterable, Codable, Sendable {
    case none
    case ssl
    case startTLS
}

public struct TransportConfiguration: Hashable, Codable, Sendable {
    public var host: String
    public var port: Int
    public var security: ConnectionSecurity
    public var allowsInvalidCertificates: Bool
    public var timeout: Double

    public init(
        host: String,
        port: Int,
        security: ConnectionSecurity,
        allowsInvalidCertificates: Bool = false,
        timeout: Double = 30
    ) {
        self.host = host
        self.port = port
        self.security = security
        self.allowsInvalidCertificates = allowsInvalidCertificates
        self.timeout = timeout
    }
}
