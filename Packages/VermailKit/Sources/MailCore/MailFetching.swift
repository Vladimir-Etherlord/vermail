import Foundation

/// A message on the server, identified by a protocol-stable id (POP3 UIDL, later IMAP UID).
public struct RemoteMessageRef: Hashable, Sendable {
    public let uid: String
    public let size: Int

    public init(uid: String, size: Int) {
        self.uid = uid
        self.size = size
    }
}

/// Protocol-agnostic incoming mail access, so IMAP can be added next to POP3.
public protocol MailFetching: Sendable {
    func listMessages() async throws -> [RemoteMessageRef]
    func fetchMessage(_ ref: RemoteMessageRef) async throws -> Data
    func deleteMessages(_ refs: [RemoteMessageRef]) async throws
}
