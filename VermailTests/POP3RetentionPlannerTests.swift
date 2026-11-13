import Foundation
import MailCore
import MailStorage
import Testing
@testable import Vermail

struct POP3RetentionPlannerTests {
    @Test func removesAgedAndLocallyDeletedCopies() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let stored = [
            POP3StoredMessage(remoteUID: "old", storedAt: now.addingTimeInterval(-15 * 86400)),
            POP3StoredMessage(remoteUID: "exact", storedAt: now.addingTimeInterval(-14 * 86400)),
            POP3StoredMessage(remoteUID: "young", storedAt: now.addingTimeInterval(-86400)),
            POP3StoredMessage(remoteUID: "gone", storedAt: nil),
        ]
        let refs = ["old", "exact", "young", "gone", "fresh"].map { RemoteMessageRef(uid: $0, size: 1) }

        let doomed = POP3RetentionPlanner.messageRefsToRemove(
            serverRefs: refs,
            stored: stored,
            policy: POP3RetentionPolicy(
                leaveMailOnServer: true,
                deleteFromServerAfterDays: 14,
                deleteWhenRemovedLocally: true
            ),
            now: now
        )

        #expect(doomed.map(\.uid) == ["old", "exact", "gone"])
    }

    @Test func keepingMailOnServerRemovesNothingWithoutAMatchingRule() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let refs = [RemoteMessageRef(uid: "fresh", size: 1)]
        let doomed = POP3RetentionPlanner.messageRefsToRemove(
            serverRefs: refs,
            stored: [],
            policy: POP3RetentionPolicy(
                leaveMailOnServer: true,
                deleteFromServerAfterDays: nil,
                deleteWhenRemovedLocally: false
            ),
            now: now
        )
        #expect(doomed.isEmpty)
    }
}
