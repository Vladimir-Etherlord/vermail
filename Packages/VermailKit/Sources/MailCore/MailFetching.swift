import Foundation

/// A message on the server, identified by a protocol-stable id (POP3 UIDL or an IMAP UID key).
public struct RemoteMessageRef: Hashable, Sendable {
    public let uid: String
    public let size: Int
    public let isRead: Bool

    public init(uid: String, size: Int, isRead: Bool = false) {
        self.uid = uid
        self.size = size
        self.isRead = isRead
    }
}

/// A server mailbox that already maps onto one shared folder.
public struct RemoteMailbox: Hashable, Sendable {
    public var name: String
    public var folder: MailFolderKind

    public init(name: String, folder: MailFolderKind) {
        self.name = name
        self.folder = folder
    }
}

/// Protocol-agnostic incoming mail access. Each account gets an implementation matching its
/// `IncomingProtocol`, so POP3 and IMAP accounts can be used side by side.
public protocol MailFetching: Sendable {
    func listMessages() async throws -> [RemoteMessageRef]
    func fetchMessage(_ ref: RemoteMessageRef) async throws -> Data
    func deleteMessages(_ refs: [RemoteMessageRef]) async throws
    /// Mailboxes the server exposes. POP3 returns an empty list and downloads the inbox only.
    func remoteMailboxes() async throws -> [RemoteMailbox]
    func selectMailbox(_ mailbox: RemoteMailbox) async throws
}

public extension MailFetching {
    func remoteMailboxes() async throws -> [RemoteMailbox] {
        []
    }

    func selectMailbox(_: RemoteMailbox) async throws {}
}
