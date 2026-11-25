import Foundation
import GRDB

struct AirmailLibrary: Sendable {
    var root: URL

    func accountEmails() throws -> [String] {
        try accountDirectories().map { AirmailLocations.email(fromAccountDirectory: $0) }
    }

    func forEachLetter(_ visitor: (AirmailLetter) async throws -> Void) async throws {
        for account in try accountDirectories() {
            try await readAccount(account, visitor: visitor)
        }
    }

    private func accountDirectories() throws -> [URL] {
        if AirmailFiles.isAccountDirectory(root) {
            return [root]
        }
        let children = try AirmailFiles.contents(of: root)
        let accounts = children.filter { AirmailFiles.isAccountDirectory($0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        if accounts.isEmpty {
            throw AirmailImportError.noAirmailAccounts(root.fileSystemPath)
        }
        return accounts
    }

    private func readAccount(
        _ account: URL,
        visitor: (AirmailLetter) async throws -> Void
    ) async throws {
        let folders = try loadFolders(account.appending(path: "Data.db"))
        let rfcStore = try AirmailRFCStore.open(account: account)
        for file in try messageFiles(account) {
            try await readShard(file, account: account, folders: folders, rfcStore: rfcStore, visitor: visitor)
        }
    }

    private func messageFiles(_ account: URL) throws -> [URL] {
        let directory = account.appending(path: "Message", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: directory.fileSystemPath) else { return [] }
        return try AirmailFiles.contents(of: directory)
            .filter { $0.pathExtension.lowercased() == "db" && $0.lastPathComponent.lowercased().hasPrefix("message") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func readShard(
        _ file: URL,
        account: URL,
        folders: [Int64: String],
        rfcStore: AirmailRFCStore,
        visitor: (AirmailLetter) async throws -> Void
    ) async throws {
        guard let queue = try AirmailSQLite.openReadOnly(file) else { return }
        let tables = try AirmailSQLite.tables(in: queue)
        guard let table = tables.first(where: {
            $0.columns.contains("messageid") && $0.columns.contains("subject") && $0.columns.contains("uidfolderid")
        }) else {
            return
        }
        let records = try fetch(queue, table: table)
        let bodies = try AirmailBodyStore.open(messageFile: file)
        let context = AirmailLetterContext(
            accountEmail: AirmailLocations.email(fromAccountDirectory: account),
            shard: file.deletingPathExtension().lastPathComponent,
            folders: folders,
            attachmentsDirectory: account.appending(path: "AttachmentsNg", directoryHint: .isDirectory)
        )
        for record in records {
            let body = try bodies.text(idx: record.idx)
            let storedRFC = try rfcStore.data(idx: record.idx)
            try await visitor(AirmailLetterBuilder.make(
                record: record,
                body: body,
                storedRFC: storedRFC,
                context: context
            ))
        }
    }

    private func fetch(_ queue: DatabaseQueue, table: AirmailTable) throws -> [AirmailMessageRecord] {
        let sql = AirmailMessageSQL.query(table: table)
        return try queue.read { database in
            try Row.fetchAll(database, sql: sql).map { AirmailMessageSQL.record(from: $0) }
        }
    }

    private func loadFolders(_ url: URL) throws -> [Int64: String] {
        guard let queue = try AirmailSQLite.openReadOnly(url) else { return [:] }
        let tables = try AirmailSQLite.tables(in: queue)
        guard let table = tables.first(where: {
            $0.columns.contains("name") && $0.columns.contains("standardfolderid")
        }) else {
            return [:]
        }
        let idx = table.columns.contains("idx") ? "idx" : "rowid"
        return try queue.read { database in
            let sql = "SELECT \(idx) AS idx, name FROM \(AirmailSQLite.quote(table.name))"
            var map: [Int64: String] = [:]
            for row in try Row.fetchAll(database, sql: sql) {
                let name: String = row["name"] ?? ""
                if !name.isEmpty {
                    map[row["idx"]] = name
                }
            }
            return map
        }
    }
}
