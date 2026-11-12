import Foundation

public struct TrafficEvent: Sendable, Equatable {
    public enum Direction: Sendable {
        case sent
        case received
    }

    public let direction: Direction
    public let text: String
}

public typealias TrafficLogger = @Sendable (TrafficEvent) -> Void

/// A line-oriented connection to a mail server. Protocol clients depend on this abstraction,
/// so they can be tested against scripted server dialogs.
public protocol MailConnection: Sendable {
    func open() async throws(TransportError)
    /// Returns the next line without its CRLF terminator.
    func readLine() async throws(TransportError) -> Data
    /// `sensitive` data (passwords, tokens) is not written to the traffic log.
    func write(_ data: Data, sensitive: Bool) async throws(TransportError)
    /// Upgrades a plain connection to TLS after a successful STARTTLS/STLS command.
    func startTLS() async throws(TransportError)
    func close() async
}

public extension MailConnection {
    func writeLine(_ line: String, sensitive: Bool = false) async throws(TransportError) {
        try await write(Data((line + "\r\n").utf8), sensitive: sensitive)
    }

    func readLineString() async throws(TransportError) -> String {
        try await String(decoding: readLine(), as: UTF8.self)
    }
}
