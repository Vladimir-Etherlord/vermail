import Foundation
import GRDB
import MailCore

public extension MailDatabase {
    func allMessageRefs() throws -> [StoredMessageRef] {
        try dbQueue.read { database in
            try Row.fetchAll(database, sql: "SELECT id, remote_uid FROM messages").map { row in
                StoredMessageRef(id: row["id"], remoteUID: row["remote_uid"])
            }
        }
    }

    func knownRemoteUIDs() throws -> Set<String> {
        try dbQueue.read { database in
            let messages = try String.fetchAll(database, sql: "SELECT remote_uid FROM messages")
            let serverUIDs = try String.fetchAll(database, sql: "SELECT remote_uid FROM pop3_uidl_state")
            return Set(messages).union(serverUIDs)
        }
    }

    func noteServerUID(_ remoteUID: String, accountID: UUID, messageID: Int64) throws {
        try dbQueue.write { database in
            try database.execute(
                sql: """
                INSERT OR IGNORE INTO pop3_uidl_state (
                    account_id, remote_uid, message_id, last_seen_at
                ) VALUES (?, ?, ?, ?)
                """,
                arguments: [accountID.uuidString, remoteUID, messageID, Date()]
            )
        }
    }

    func messages(withIDs ids: [Int64]) throws -> [StoredMessage] {
        if ids.isEmpty {
            return []
        }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        var args: StatementArguments = []
        for id in ids {
            args += [id]
        }
        return try dbQueue.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: "SELECT * FROM messages WHERE id IN (\(placeholders))",
                arguments: args
            )
            return try rows.map(messageFromRow)
        }
    }

    func relocateMessage(id: Int64, remoteUID: String, folder: MailFolderKind) throws {
        try dbQueue.write { database in
            try database.execute(
                sql: "UPDATE pop3_uidl_state SET remote_uid = ? WHERE message_id = ?",
                arguments: [remoteUID, id]
            )
            try database.execute(
                sql: """
                UPDATE messages
                SET remote_uid = ?, folder = ?, updated_at = ?
                WHERE id = ?
                """,
                arguments: [remoteUID, folder.rawValue, Date(), id]
            )
        }
    }

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
        try folderCounts(accounts: accounts, unreadOnly: true)
    }

    func messageCounts(accounts: [MailAccount]) throws -> UnreadCounts {
        try folderCounts(accounts: accounts, unreadOnly: false)
    }

    private func folderCounts(accounts: [MailAccount], unreadOnly: Bool) throws -> UnreadCounts {
        let filter = unreadOnly ? "WHERE is_read = 0" : ""
        let rows = try dbQueue.read { database in
            try Row.fetchAll(
                database,
                sql: """
                SELECT account_id, folder, COUNT(*) AS message_count
                FROM messages
                \(filter)
                GROUP BY account_id, folder
                """
            )
        }
        let unifiedIDs = Set(accounts.filter(\.isIncludedInUnifiedFolders).map(\.id))
        return FolderCountFold(unifiedAccountIDs: unifiedIDs).counts(from: rows)
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

private struct FolderCountFold {
    var unifiedAccountIDs: Set<UUID>

    func counts(from rows: [Row]) -> UnreadCounts {
        var byAccount: [UUID: [MailFolderKind: Int]] = [:]
        var unified: [MailFolderKind: Int] = [:]
        for row in rows {
            guard let counted = CountedFolder(row) else { continue }
            record(counted, byAccount: &byAccount, unified: &unified)
        }
        return UnreadCounts(unified: unified, byAccount: byAccount)
    }

    private func record(
        _ counted: CountedFolder,
        byAccount: inout [UUID: [MailFolderKind: Int]],
        unified: inout [MailFolderKind: Int]
    ) {
        byAccount[counted.accountID, default: [:]][counted.folder, default: 0] += counted.count
        if counted.folder != .trash, counted.folder != .spam {
            byAccount[counted.accountID, default: [:]][.allMail, default: 0] += counted.count
        }
        guard unifiedAccountIDs.contains(counted.accountID) else { return }
        unified[counted.folder, default: 0] += counted.count
        if counted.folder != .trash, counted.folder != .spam {
            unified[.allMail, default: 0] += counted.count
        }
    }
}

private struct CountedFolder {
    var accountID: UUID
    var folder: MailFolderKind
    var count: Int

    init?(_ row: Row) {
        let accountRaw: String = row["account_id"]
        let folderRaw: String = row["folder"]
        guard let accountID = UUID(uuidString: accountRaw),
              let folder = MailFolderKind(rawValue: folderRaw)
        else {
            return nil
        }
        self.accountID = accountID
        self.folder = folder
        count = row["message_count"]
    }
}
