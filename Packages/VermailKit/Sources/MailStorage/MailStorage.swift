import CryptoKit
import Foundation
import GRDB
import MailCore

public actor MailDatabase {
    private struct PersistedRawMessage {
        let relativePath: String
        let sizeBytes: Int
    }

    private let rootDirectory: URL
    private let fileManager: FileManager
    private let dbQueue: DatabaseQueue

    public init(rootDirectory: URL) throws {
        self.rootDirectory = rootDirectory
        fileManager = .default

        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let rawRoot = rootDirectory.appending(path: "raw", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: rawRoot, withIntermediateDirectories: true)

        let dbURL = rootDirectory.appending(path: "storage.sqlite")
        dbQueue = try DatabaseQueue(path: dbURL.path())
        try Self.makeMigrator().migrate(dbQueue)
    }

    public func upsertMessage(_ input: StoredMessageInput) throws -> StoredMessage {
        let raw = try persistRawSource(input)
        let messageID = try upsertMessageRecord(input, raw: raw)

        guard let stored = try message(byID: messageID) else {
            throw MailStorageError.messageNotFound(messageID)
        }
        return stored
    }

    public func messages(
        in mailbox: Mailbox,
        accounts: [MailAccount],
        limit: Int = 200,
        offset: Int = 0
    ) throws -> [StoredMessage] {
        let accountIDs = accountIDs(for: mailbox, accounts: accounts)
        if accountIDs.isEmpty {
            return []
        }

        let placeholders = Array(repeating: "?", count: accountIDs.count).joined(separator: ",")
        var args: StatementArguments = [mailbox.folder.rawValue]
        for accountID in accountIDs {
            args += [accountID.uuidString]
        }
        args += [limit, offset]

        return try dbQueue.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: """
                SELECT * FROM messages
                WHERE folder = ? AND account_id IN (
                    \(placeholders)
                )
                ORDER BY received_at DESC, id DESC
                LIMIT ? OFFSET ?
                """,
                arguments: args
            )
            return try rows.map(messageFromRow)
        }
    }

    public func searchMessages(
        query: String,
        in mailbox: Mailbox,
        accounts: [MailAccount],
        limit: Int = 100
    ) throws -> [StoredMessage] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return try messages(in: mailbox, accounts: accounts, limit: limit, offset: 0)
        }

        let accountIDs = accountIDs(for: mailbox, accounts: accounts)
        if accountIDs.isEmpty {
            return []
        }

        let placeholders = Array(repeating: "?", count: accountIDs.count).joined(separator: ",")
        var args: StatementArguments = [trimmed, mailbox.folder.rawValue]
        for accountID in accountIDs {
            args += [accountID.uuidString]
        }
        args += [limit]

        return try dbQueue.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: """
                SELECT m.*
                FROM message_search s
                JOIN messages m ON m.id = s.rowid
                WHERE message_search MATCH ?
                  AND m.folder = ?
                  AND m.account_id IN (
                    \(placeholders)
                  )
                ORDER BY bm25(message_search), m.received_at DESC, m.id DESC
                LIMIT ?
                """,
                arguments: args
            )
            return try rows.map(messageFromRow)
        }
    }

    public func rawMessageData(id: Int64) throws -> Data {
        guard let relativePath: String = try dbQueue.read({ database in
            try String.fetchOne(database, sql: "SELECT raw_file_path FROM messages WHERE id = ?", arguments: [id])
        }) else {
            throw MailStorageError.messageNotFound(id)
        }

        let path = rootDirectory.appending(path: relativePath)
        return try Data(contentsOf: path)
    }

    public func pop3SyncPlan(accountID: UUID, serverRefs: [RemoteMessageRef]) throws -> POP3SyncPlan {
        let knownUIDs: Set<String> = try dbQueue.read { database in
            let rows = try String.fetchAll(
                database,
                sql: "SELECT remote_uid FROM pop3_uidl_state WHERE account_id = ?",
                arguments: [accountID.uuidString]
            )
            return Set(rows)
        }

        let serverUIDs = Set(serverRefs.map(\.uid))
        let toDownload = serverRefs.filter { !knownUIDs.contains($0.uid) }
        let alreadyKnown = serverRefs.filter { knownUIDs.contains($0.uid) }
        let missingOnServer = Array(knownUIDs.subtracting(serverUIDs)).sorted()

        return POP3SyncPlan(
            toDownload: toDownload,
            alreadyKnown: alreadyKnown,
            missingOnServer: missingOnServer
        )
    }

    public func removeMessages(accountID: UUID, remoteUIDs: [String]) throws {
        if remoteUIDs.isEmpty {
            return
        }

        let placeholders = Array(repeating: "?", count: remoteUIDs.count).joined(separator: ",")
        var args: StatementArguments = [accountID.uuidString]
        for uid in remoteUIDs {
            args += [uid]
        }

        let rawPaths: [String] = try dbQueue.write { database in
            let rows = try String.fetchAll(
                database,
                sql: """
                SELECT raw_file_path FROM messages
                WHERE account_id = ? AND remote_uid IN (
                    \(placeholders)
                )
                """,
                arguments: args
            )

            try database.execute(
                sql: """
                DELETE FROM messages
                WHERE account_id = ? AND remote_uid IN (
                    \(placeholders)
                )
                """,
                arguments: args
            )

            try database.execute(
                sql: """
                DELETE FROM pop3_uidl_state
                WHERE account_id = ? AND remote_uid IN (
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
}

private extension MailDatabase {
    private func persistRawSource(_ input: StoredMessageInput) throws -> PersistedRawMessage {
        let relativePath = rawFilePath(accountID: input.accountID, remoteUID: input.remoteUID)
        let absolutePath = rootDirectory.appending(path: relativePath)
        try fileManager.createDirectory(at: absolutePath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try input.rawSource.write(to: absolutePath, options: .atomic)
        return PersistedRawMessage(relativePath: relativePath, sizeBytes: input.rawSource.count)
    }

    private func upsertMessageRecord(_ input: StoredMessageInput, raw: PersistedRawMessage) throws -> Int64 {
        let now = Date()
        let toAddressesRaw = input.toAddresses.joined(separator: ",")

        return try dbQueue.write { database in
            try upsertMessageRow(
                in: database,
                input: input,
                toAddressesRaw: toAddressesRaw,
                raw: raw,
                timestamp: now
            )

            let messageID = try fetchMessageID(in: database, accountID: input.accountID, remoteUID: input.remoteUID)
            try upsertUIDLState(
                in: database,
                accountID: input.accountID,
                remoteUID: input.remoteUID,
                messageID: messageID,
                timestamp: now
            )

            return messageID
        }
    }

    private func upsertMessageRow(
        in database: Database,
        input: StoredMessageInput,
        toAddressesRaw: String,
        raw: PersistedRawMessage,
        timestamp: Date
    ) throws {
        try database.execute(
            sql: """
            INSERT INTO messages (
                account_id, remote_uid, folder, subject, from_address, to_addresses,
                snippet, received_at, is_read, has_attachments,
                raw_file_path, size_bytes, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(account_id, remote_uid) DO UPDATE SET
                folder = excluded.folder,
                subject = excluded.subject,
                from_address = excluded.from_address,
                to_addresses = excluded.to_addresses,
                snippet = excluded.snippet,
                received_at = excluded.received_at,
                is_read = excluded.is_read,
                has_attachments = excluded.has_attachments,
                raw_file_path = excluded.raw_file_path,
                size_bytes = excluded.size_bytes,
                updated_at = excluded.updated_at
            """,
            arguments: [
                input.accountID.uuidString,
                input.remoteUID,
                input.folder.rawValue,
                input.subject,
                input.fromAddress,
                toAddressesRaw,
                input.snippet,
                input.receivedAt,
                input.isRead,
                input.hasAttachments,
                raw.relativePath,
                raw.sizeBytes,
                timestamp,
                timestamp,
            ]
        )
    }

    private func fetchMessageID(in database: Database, accountID: UUID, remoteUID: String) throws -> Int64 {
        try Int64.fetchOne(
            database,
            sql: "SELECT id FROM messages WHERE account_id = ? AND remote_uid = ?",
            arguments: [accountID.uuidString, remoteUID]
        )!
    }

    private func upsertUIDLState(
        in database: Database,
        accountID: UUID,
        remoteUID: String,
        messageID: Int64,
        timestamp: Date
    ) throws {
        try database.execute(
            sql: """
            INSERT INTO pop3_uidl_state (account_id, remote_uid, message_id, last_seen_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(account_id, remote_uid) DO UPDATE SET
                message_id = excluded.message_id,
                last_seen_at = excluded.last_seen_at
            """,
            arguments: [accountID.uuidString, remoteUID, messageID, timestamp]
        )
    }

    func accountIDs(for mailbox: Mailbox, accounts: [MailAccount]) -> [UUID] {
        switch mailbox.scope {
        case .unified:
            accounts.filter(\.isIncludedInUnifiedFolders).map(\.id)
        case let .account(id):
            [id]
        }
    }

    func rawFilePath(accountID: UUID, remoteUID: String) -> String {
        let digest = SHA256.hash(data: Data(remoteUID.utf8)).map { String(format: "%02x", $0) }.joined()
        return "raw/\(accountID.uuidString)/\(digest).eml"
    }

    func message(byID id: Int64) throws -> StoredMessage? {
        try dbQueue.read { database in
            guard let row = try Row.fetchOne(database, sql: "SELECT * FROM messages WHERE id = ?", arguments: [id])
            else {
                return nil
            }
            return try messageFromRow(row)
        }
    }

    func messageFromRow(_ row: Row) throws -> StoredMessage {
        let accountRaw: String = row["account_id"]
        guard let accountID = UUID(uuidString: accountRaw) else {
            throw MailStorageError.invalidAccountIdentifier(accountRaw)
        }

        let folderRaw: String = row["folder"]
        guard let folder = MailFolderKind(rawValue: folderRaw) else {
            throw MailStorageError.invalidFolder(folderRaw)
        }

        let toAddressesRaw: String = row["to_addresses"]
        let toAddresses = toAddressesRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return StoredMessage(
            id: row["id"],
            accountID: accountID,
            remoteUID: row["remote_uid"],
            folder: folder,
            subject: row["subject"],
            fromAddress: row["from_address"],
            toAddresses: toAddresses,
            snippet: row["snippet"],
            receivedAt: row["received_at"],
            isRead: row["is_read"],
            hasAttachments: row["has_attachments"],
            rawFilePath: row["raw_file_path"],
            sizeBytes: row["size_bytes"]
        )
    }
}
