import Foundation
import MailCore
import MailStorage

struct MailAlert: Equatable, Sendable {
    var identifier: String
    var title: String
    var subtitle: String?
    var body: String
}

enum MailAlertPlanner {
    static let individualLimit = 3

    static func makeAlerts(
        from notices: [IncomingMailNotice],
        accountNames: [UUID: String]
    ) -> [MailAlert] {
        let fresh = notices
            .filter(\.announcesArrival)
            .sorted { $0.remoteUID < $1.remoteUID }
        guard !fresh.isEmpty else { return [] }
        if fresh.count > individualLimit {
            return [summary(of: fresh)]
        }
        let showsAccount = accountNames.count > 1
        return fresh.map { notice in
            individual(notice, accountName: showsAccount ? accountNames[notice.accountID] : nil)
        }
    }

    private static func summary(of notices: [IncomingMailNotice]) -> MailAlert {
        let first = notices[0]
        return MailAlert(
            identifier: "mail-summary-\(notices.count)-\(first.remoteUID)",
            title: String(localized: "\(notices.count) new messages"),
            subtitle: nil,
            body: "\(senderName(from: first.fromAddress)): \(preview(of: first))"
        )
    }

    private static func individual(_ notice: IncomingMailNotice, accountName: String?) -> MailAlert {
        MailAlert(
            identifier: "\(notice.accountID.uuidString)|\(notice.remoteUID)",
            title: senderName(from: notice.fromAddress),
            subtitle: accountName,
            body: preview(of: notice)
        )
    }

    private static func preview(of notice: IncomingMailNotice) -> String {
        let subject = notice.subject?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !subject.isEmpty {
            return subject
        }
        let snippet = notice.snippet?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !snippet.isEmpty {
            return snippet
        }
        return String(localized: "(No Subject)")
    }

    static func senderName(from raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return String(localized: "New Message")
        }
        guard let bracket = trimmed.firstIndex(of: "<") else {
            return trimmed
        }
        let name = trimmed[..<bracket]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return name.isEmpty ? trimmed : name
    }
}

enum DockBadgeText {
    static func label(unreadCount: Int, isVisible: Bool) -> String? {
        guard isVisible, unreadCount > 0 else { return nil }
        if unreadCount > 999 {
            return "999+"
        }
        return unreadCount.formatted()
    }

    static func inboxUnreadCount(in counts: UnreadCounts, accounts: [MailAccount]) -> Int {
        accounts.reduce(into: 0) { total, account in
            guard account.isEnabled else { return }
            let mailbox = Mailbox(folder: .inbox, scope: .account(account.id))
            total += counts.count(for: mailbox)
        }
    }
}
