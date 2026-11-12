import Foundation

public enum MailAutoconfigSource: String, Sendable {
    case preset
    case ispdb
}

public struct MailAutoconfigResult: Sendable, Hashable {
    public var source: MailAutoconfigSource
    public var domain: String
    public var incomingCandidates: [IncomingServerSettings]
    public var outgoing: OutgoingServerSettings?

    public init(
        source: MailAutoconfigSource,
        domain: String,
        incomingCandidates: [IncomingServerSettings],
        outgoing: OutgoingServerSettings?
    ) {
        self.source = source
        self.domain = domain
        self.incomingCandidates = incomingCandidates
        self.outgoing = outgoing
    }

    public func bestIncoming(preferred: IncomingProtocol) -> IncomingServerSettings? {
        incomingCandidates.first(where: { $0.protocolKind == preferred }) ?? incomingCandidates.first
    }
}

public enum MailAutoconfigError: Error, Equatable, Sendable {
    case invalidEmailAddress(String)
    case invalidHTTPResponse
    case badHTTPStatus(Int)
    case malformedXML
}
