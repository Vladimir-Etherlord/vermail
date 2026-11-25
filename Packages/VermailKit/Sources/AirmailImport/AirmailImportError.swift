import Foundation

public struct AirmailImportReport: Sendable, Equatable {
    public var scanned: Int
    public var imported: Int
    public var alreadyPresent: Int
    public var skippedEmpty: Int
    public var failed: Int

    public init(
        scanned: Int = 0,
        imported: Int = 0,
        alreadyPresent: Int = 0,
        skippedEmpty: Int = 0,
        failed: Int = 0
    ) {
        self.scanned = scanned
        self.imported = imported
        self.alreadyPresent = alreadyPresent
        self.skippedEmpty = skippedEmpty
        self.failed = failed
    }
}

public enum AirmailImportError: Error, Equatable, CustomStringConvertible {
    case unreadableLibrary(String)
    case noAirmailAccounts(String)
    case noVermailAccounts(String)
    case accountNotFound(String)
    case ambiguousAccounts
    case invalidArguments(String)

    public var description: String {
        switch self {
        case let .unreadableLibrary(path):
            """
            Airmail's mail library is not readable (\(path)).
            Grant Full Disk Access to the app that runs this command
            (System Settings → Privacy & Security → Full Disk Access), then run it again.
            """
        case let .noAirmailAccounts(path):
            "No Airmail account was found in \(path)."
        case let .noVermailAccounts(path):
            "No Vermail accounts were found in \(path)."
        case let .accountNotFound(email):
            "No account matches \(email)."
        case .ambiguousAccounts:
            "More than one account matches. Pass --account-email."
        case let .invalidArguments(flag):
            "Unknown argument: \(flag)"
        }
    }
}
