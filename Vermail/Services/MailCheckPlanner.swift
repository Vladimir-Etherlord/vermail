import Foundation
import MailCore

enum MailCheckPlanner {
    static func dueAccounts(
        among accounts: [MailAccount],
        lastCheckedAt: [UUID: Date],
        now: Date,
        includesAllEnabled: Bool
    ) -> [MailAccount] {
        accounts.filter { account in
            isDue(
                account,
                lastCheckedAt: lastCheckedAt[account.id],
                now: now,
                includesAllEnabled: includesAllEnabled
            )
        }
    }

    private static func isDue(
        _ account: MailAccount,
        lastCheckedAt: Date?,
        now: Date,
        includesAllEnabled: Bool
    ) -> Bool {
        guard account.isEnabled else { return false }
        if includesAllEnabled {
            return true
        }
        guard let lastCheckedAt else { return true }
        return now.timeIntervalSince(lastCheckedAt) >= interval(for: account)
    }

    private static func interval(for account: MailAccount) -> TimeInterval {
        let minutes = account.details?.checkIntervalMinutes ?? 5
        return TimeInterval(max(minutes, 1) * 60)
    }
}
