import Foundation
import MailCore

public enum MailStorageError: Error, Equatable, Sendable {
    case invalidFolder(String)
    case invalidAccountIdentifier(String)
    case messageNotFound(Int64)
}

public struct StoredMessage: Identifiable, Sendable, Equatable {
    public let id: Int64
    public let accountID: UUID
    public let remoteUID: String
    public let folder: MailFolderKind
    public let subject: String?
    public let fromAddress: String?
    public let toAddresses: [String]
    public let snippet: String?
    public let receivedAt: Date?
    public let isRead: Bool
    public let hasAttachments: Bool
    public let rawFilePath: String
    public let sizeBytes: Int

    public init(
        id: Int64,
        accountID: UUID,
        remoteUID: String,
        folder: MailFolderKind,
        subject: String?,
        fromAddress: String?,
        toAddresses: [String],
        snippet: String?,
        receivedAt: Date?,
        isRead: Bool,
        hasAttachments: Bool,
        rawFilePath: String,
        sizeBytes: Int
    ) {
        self.id = id
        self.accountID = accountID
        self.remoteUID = remoteUID
        self.folder = folder
        self.subject = subject
        self.fromAddress = fromAddress
        self.toAddresses = toAddresses
        self.snippet = snippet
        self.receivedAt = receivedAt
        self.isRead = isRead
        self.hasAttachments = hasAttachments
        self.rawFilePath = rawFilePath
        self.sizeBytes = sizeBytes
    }
}

public struct StoredMessageInput: Sendable {
    public var accountID: UUID
    public var remoteUID: String
    public var folder: MailFolderKind
    public var subject: String?
    public var fromAddress: String?
    public var toAddresses: [String]
    public var snippet: String?
    public var receivedAt: Date?
    public var isRead: Bool
    public var hasAttachments: Bool
    public var rawSource: Data

    public init(
        accountID: UUID,
        remoteUID: String,
        folder: MailFolderKind,
        subject: String?,
        fromAddress: String?,
        toAddresses: [String],
        snippet: String?,
        receivedAt: Date?,
        isRead: Bool = false,
        hasAttachments: Bool = false,
        rawSource: Data
    ) {
        self.accountID = accountID
        self.remoteUID = remoteUID
        self.folder = folder
        self.subject = subject
        self.fromAddress = fromAddress
        self.toAddresses = toAddresses
        self.snippet = snippet
        self.receivedAt = receivedAt
        self.isRead = isRead
        self.hasAttachments = hasAttachments
        self.rawSource = rawSource
    }
}

public struct POP3SyncPlan: Sendable, Equatable {
    public var toDownload: [RemoteMessageRef]
    public var alreadyKnown: [RemoteMessageRef]
    public var missingOnServer: [String]

    public init(toDownload: [RemoteMessageRef], alreadyKnown: [RemoteMessageRef], missingOnServer: [String]) {
        self.toDownload = toDownload
        self.alreadyKnown = alreadyKnown
        self.missingOnServer = missingOnServer
    }
}

public struct UnreadCounts: Sendable, Equatable {
    public var unified: [MailFolderKind: Int]
    public var byAccount: [UUID: [MailFolderKind: Int]]

    public init(
        unified: [MailFolderKind: Int] = [:],
        byAccount: [UUID: [MailFolderKind: Int]] = [:]
    ) {
        self.unified = unified
        self.byAccount = byAccount
    }

    public func count(for mailbox: Mailbox) -> Int {
        switch mailbox.scope {
        case .unified:
            unified[mailbox.folder, default: 0]
        case let .account(accountID):
            byAccount[accountID]?[mailbox.folder, default: 0] ?? 0
        }
    }
}

public enum MailStorage {
    /// Root directory for database and raw `.eml` files.
    public static func defaultRootDirectory(fileManager: FileManager = .default) throws -> URL {
        try fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Vermail", directoryHint: .isDirectory)
    }

    public static func open(rootDirectory: URL? = nil) throws -> MailDatabase {
        let root = try rootDirectory ?? defaultRootDirectory()
        return try MailDatabase(rootDirectory: root)
    }
}
