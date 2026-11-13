import Foundation
import MailCore

extension IMAPClient {
    public func setRead(_ isRead: Bool, refs: [RemoteMessageRef]) async throws {
        if refs.isEmpty {
            return
        }
        try await ensureAuthenticated()
        let groups = Dictionary(grouping: refs) { IMAPMessageKey.parse($0.uid)?.mailbox ?? "" }
        for (mailbox, group) in groups {
            try await storeSeen(isRead, refs: group, mailbox: mailbox)
        }
    }

    public func moveMessages(
        _ refs: [RemoteMessageRef],
        to mailbox: RemoteMailbox
    ) async throws -> [RemoteMessageMove] {
        if refs.isEmpty {
            return []
        }
        try await ensureAuthenticated()
        try await loadCapabilities()
        let groups = Dictionary(grouping: refs) { IMAPMessageKey.parse($0.uid)?.mailbox ?? "" }
        var moved: [RemoteMessageMove] = []
        for (source, group) in groups {
            let changes = try await move(group, from: source, to: mailbox)
            moved.append(contentsOf: changes)
        }
        return moved
    }

    func storeSeen(_ isRead: Bool, refs: [RemoteMessageRef], mailbox: String) async throws {
        guard !mailbox.isEmpty else { throw IMAPError.messageNotFound(refs[0].uid) }
        let uids = try refs.map { ref -> String in
            guard let uid = IMAPMessageKey.parse(ref.uid)?.uid else {
                throw IMAPError.messageNotFound(ref.uid)
            }
            return uid
        }
        try await select(rawName: mailbox)
        let verb = isRead ? "+FLAGS.SILENT" : "-FLAGS.SILENT"
        var start = 0
        while start < uids.count {
            let end = min(start + 50, uids.count)
            let set = uids[start ..< end].joined(separator: ",")
            _ = try await send("UID STORE \(set) \(verb) (\\Seen)")
            start = end
        }
    }

    func move(
        _ refs: [RemoteMessageRef],
        from mailbox: String,
        to destination: RemoteMailbox
    ) async throws -> [RemoteMessageMove] {
        guard !mailbox.isEmpty else { throw IMAPError.messageNotFound(refs[0].uid) }
        let destinationName = IMAPParser.canonicalMailbox(destination.name)
        var moved: [RemoteMessageMove] = []
        for ref in refs {
            guard let key = IMAPMessageKey.parse(ref.uid) else { throw IMAPError.messageNotFound(ref.uid) }
            let change = try await moveOne(key, to: destinationName)
            moved.append(RemoteMessageMove(sourceUID: ref.uid, destinationUID: change))
        }
        return moved
    }

    func moveOne(_ key: IMAPMessageKey, to destinationName: String) async throws -> String {
        try await select(rawName: key.mailbox)
        let quoted = IMAPParser.quote(destinationName)
        let reply: IMAPReply
        if capabilities.contains("MOVE") {
            reply = try await send("UID MOVE \(key.uid) \(quoted)")
        } else {
            reply = try await send("UID COPY \(key.uid) \(quoted)")
            try await expunge([key.uid])
        }
        guard let copied = copyResult(in: reply), let newUID = copied.destination.first else {
            throw IMAPError.invalidResponse(reply.statusText)
        }
        let stored = IMAPMessageKey(mailbox: destinationName, uidValidity: copied.uidValidity, uid: newUID)
        return stored.storageValue
    }

    func copyResult(in reply: IMAPReply) -> IMAPCopyResult? {
        if let parsed = IMAPParser.copyUID(in: reply.statusText) {
            return parsed
        }
        return reply.lines.compactMap { IMAPParser.copyUID(in: $0.text) }.first
    }
}
