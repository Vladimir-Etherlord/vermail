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
            if fileManager.fileExists(atPath: full.fileSystemPath) {
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

    func pop3StoredMessages(accountID: UUID, remoteUIDs: [String]) throws -> [POP3StoredMessage] {
        guard !remoteUIDs.isEmpty else { return [] }
        var stored: [POP3StoredMessage] = []
        let chunkSize = 200
        var offset = 0
        while offset < remoteUIDs.count {
            let end = min(offset + chunkSize, remoteUIDs.count)
            let chunk = Array(remoteUIDs[offset ..< end])
            try stored.append(contentsOf: fetchPOP3StoredMessages(accountID: accountID, remoteUIDs: chunk))
            offset = end
        }
        return stored
    }

    static func ftsMatchQuery(_ raw: String) -> String? {
        let tokens = raw.split(whereSeparator: \.isWhitespace).compactMap { token -> String? in
            let cleaned = token.filter { character in
                character.isLetter || character.isNumber || ".-_@".contains(character)
            }
            return cleaned.isEmpty ? nil : String(cleaned)
        }
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " ")
    }

    private func fetchPOP3StoredMessages(accountID: UUID, remoteUIDs: [String]) throws -> [POP3StoredMessage] {
        let placeholders = Array(repeating: "?", count: remoteUIDs.count).joined(separator: ",")
        var args: StatementArguments = [accountID.uuidString]
        for uid in remoteUIDs {
            args += [uid]
        }
        return try dbQueue.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: """
                SELECT u.remote_uid AS remote_uid, m.created_at AS stored_at
                FROM pop3_uidl_state u
                LEFT JOIN messages m ON m.id = u.message_id
                WHERE u.account_id = ? AND u.remote_uid IN (
                    \(placeholders)
                )
                """,
                arguments: args
            )
            return rows.map { row in
                let remoteUID: String = row["remote_uid"]
                let storedAt: Date? = row["stored_at"]
                return POP3StoredMessage(remoteUID: remoteUID, storedAt: storedAt)
            }
        }
    }
}
