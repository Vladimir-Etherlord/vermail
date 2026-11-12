import Foundation

public struct AccountDetails: Hashable, Codable, Sendable {
    public var summary: String
    public var symbolName: String
    public var colorName: String
    public var incomingUsername: String
    public var outgoingUsername: String
    public var allowsInvalidCertificates: Bool
    public var checkIntervalMinutes: Int
    public var leaveMailOnServer: Bool
    public var deleteFromServerAfterDays: Int?
    public var deleteFromServerWhenDeletedLocally: Bool

    public init(
        summary: String = "",
        symbolName: String = "envelope.fill",
        colorName: String = "blue",
        incomingUsername: String = "",
        outgoingUsername: String = "",
        allowsInvalidCertificates: Bool = false,
        checkIntervalMinutes: Int = 5,
        leaveMailOnServer: Bool = true,
        deleteFromServerAfterDays: Int? = nil,
        deleteFromServerWhenDeletedLocally: Bool = false
    ) {
        self.summary = summary
        self.symbolName = symbolName
        self.colorName = colorName
        self.incomingUsername = incomingUsername
        self.outgoingUsername = outgoingUsername
        self.allowsInvalidCertificates = allowsInvalidCertificates
        self.checkIntervalMinutes = checkIntervalMinutes
        self.leaveMailOnServer = leaveMailOnServer
        self.deleteFromServerAfterDays = deleteFromServerAfterDays
        self.deleteFromServerWhenDeletedLocally = deleteFromServerWhenDeletedLocally
    }
}
