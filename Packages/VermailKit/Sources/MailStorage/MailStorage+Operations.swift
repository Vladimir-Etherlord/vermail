import Foundation
import GRDB
import MailCore

public extension MailDatabase {
    func setRead(_ isRead: Bool, messageIDs: [Int64]) throws {
        if messageIDs.isEmpty {
            return
        }

        let placeholders = Array(repeating: "?", count: messageIDs.count).joined(separator: ",")
        var args: StatementArguments = [isRead, Date()]
        for messageID in messageIDs {
            args += [messageID]
        }

        try dbQueue.write { database in
            try database.execute(
                sql: """
                UPDATE messages
                SET is_read = ?, updated_at = ?
                WHERE id IN (
                    \(placeholders)
                )
                """,
                arguments: args
            )
        }
    }

    func moveMessages(ids: [Int64], to folder: MailFolderKind) throws {
        if ids.isEmpty {
            return
        }

        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        var args: StatementArguments = [folder.rawValue, Date()]
        for id in ids {
            args += [id]
        }

        try dbQueue.write { database in
            try database.execute(
                sql: """
                UPDATE messages
                SET folder = ?, updated_at = ?
                WHERE id IN (
                    \(placeholders)
                )
                """,
                arguments: args
            )
        }
    }

    func deleteMessages(ids: [Int64]) throws {
        if ids.isEmpty {
            return
        }

        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        var args: StatementArguments = []
        for id in ids {
            args += [id]
        }

        let rawPaths: [String] = try dbQueue.write { database in
            let rows = try String.fetchAll(
                database,
                sql: """
                SELECT raw_file_path FROM messages
                WHERE id IN (
                    \(placeholders)
                )
                """,
                arguments: args
            )

            try database.execute(
                sql: """
                DELETE FROM messages
                WHERE id IN (
                    \(placeholders)
                )
                """,
                arguments: args
            )

            return rows
        }

        for rawPath in rawPaths {
            let full = rootDirectory.appending(path: rawPath)
            if fileManager.fileExists(atPath: full.path()) {
                try fileManager.removeItem(at: full)
            }
        }
    }

    func unreadCounts(accounts: [MailAccount]) throws -> UnreadCounts {
        let rows = try dbQueue.read { database in
            try Row.fetchAll(
                database,
                sql: """
                SELECT account_id, folder, COUNT(*) AS unread_count
                FROM messages
                WHERE is_read = 0
                GROUP BY account_id, folder
                """
            )
        }

        let includedUnifiedIDs = Set(accounts.filter(\.isIncludedInUnifiedFolders).map(\.id))
        var byAccount: [UUID: [MailFolderKind: Int]] = [:]
        var unified: [MailFolderKind: Int] = [:]

        for row in rows {
            let accountRaw: String = row["account_id"]
            let folderRaw: String = row["folder"]
            let count: Int = row["unread_count"]
            guard let accountID = UUID(uuidString: accountRaw),
                  let folder = MailFolderKind(rawValue: folderRaw)
            else {
                continue
            }

            byAccount[accountID, default: [:]][folder, default: 0] += count
            if folder != .trash, folder != .spam {
                byAccount[accountID, default: [:]][.allMail, default: 0] += count
            }

            if includedUnifiedIDs.contains(accountID) {
                unified[folder, default: 0] += count
                if folder != .trash, folder != .spam {
                    unified[.allMail, default: 0] += count
                }
            }
        }

        return UnreadCounts(unified: unified, byAccount: byAccount)
    }
}
