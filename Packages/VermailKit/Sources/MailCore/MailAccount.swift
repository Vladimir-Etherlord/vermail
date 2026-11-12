import Foundation

public enum IncomingProtocol: String, CaseIterable, Codable, Sendable {
    case pop3
    case imap
}

public struct MailAccount: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var displayName: String
    public var emailAddress: String
    public var incomingProtocol: IncomingProtocol
    public var isIncludedInUnifiedFolders: Bool

    public init(
        id: UUID = UUID(),
        displayName: String,
        emailAddress: String,
        incomingProtocol: IncomingProtocol,
        isIncludedInUnifiedFolders: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.emailAddress = emailAddress
        self.incomingProtocol = incomingProtocol
        self.isIncludedInUnifiedFolders = isIncludedInUnifiedFolders
    }
}
