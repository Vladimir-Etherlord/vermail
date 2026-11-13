import Foundation
import MailCore
import MailStorage

struct POP3RetentionPolicy: Equatable, Sendable {
    var leaveMailOnServer: Bool
    var deleteFromServerAfterDays: Int?
    var deleteWhenRemovedLocally: Bool
}

enum POP3RetentionPlanner {
    static func messageRefsToRemove(
        serverRefs: [RemoteMessageRef],
        stored: [POP3StoredMessage],
        policy: POP3RetentionPolicy,
        now: Date
    ) -> [RemoteMessageRef] {
        let byUID = Dictionary(stored.map { ($0.remoteUID, $0) }, uniquingKeysWith: { first, _ in first })
        return serverRefs.filter { ref in
            shouldRemove(record: byUID[ref.uid], policy: policy, now: now)
        }
    }

    private static func shouldRemove(
        record: POP3StoredMessage?,
        policy: POP3RetentionPolicy,
        now: Date
    ) -> Bool {
        guard let record else { return false }
        if !policy.leaveMailOnServer {
            return true
        }
        if policy.deleteWhenRemovedLocally, record.storedAt == nil {
            return true
        }
        guard let days = policy.deleteFromServerAfterDays, days > 0, let storedAt = record.storedAt else {
            return false
        }
        return now.timeIntervalSince(storedAt) >= TimeInterval(days) * 86400
    }
}
