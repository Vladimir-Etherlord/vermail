import Foundation
import GRDB

struct AirmailBodyText {
    var plain: String
    var html: String

    /// Airmail often stores the same HTML document in both columns. Keep one HTML part so the
    /// viewer renders it instead of showing the markup as plain text.
    static func rendered(plain: String, html: String) -> AirmailBodyText {
        if !html.isEmpty {
            return AirmailBodyText(plain: isHTML(plain) ? "" : plain, html: html)
        }
        if isHTML(plain) {
            return AirmailBodyText(plain: "", html: plain)
        }
        return AirmailBodyText(plain: plain, html: html)
    }

    private static func isHTML(_ value: String) -> Bool {
        let head = value.prefix(32).lowercased()
        let markers = ["<!doctype", "<html", "<body", "<div", "<table", "<p", "<span", "<br"]
        return markers.contains { head.hasPrefix($0) }
    }
}

struct AirmailBodyStore {
    var queue: DatabaseQueue?
    var table: String?
    var columns: Set<String>

    func text(idx: Int64) throws -> AirmailBodyText {
        guard let queue, let table else { return AirmailBodyText(plain: "", html: "") }
        let sql = Self.query(table: table, columns: columns)
        return try queue.read { database in
            guard let row = try Row.fetchOne(database, sql: sql, arguments: [idx]) else {
                return AirmailBodyText(plain: "", html: "")
            }
            return Self.text(from: row, columns: columns)
        }
    }

    static func open(messageFile: URL) throws -> AirmailBodyStore {
        let bodyURL = pairedURL(messageFile)
        guard let queue = try AirmailSQLite.openReadOnly(bodyURL) else {
            return AirmailBodyStore(queue: nil, table: nil, columns: [])
        }
        let tables = try AirmailSQLite.tables(in: queue)
        guard let table = tables.first(where: { $0.columns.contains("plainbody") && $0.columns.contains("htmlbody") })
        else {
            return AirmailBodyStore(queue: nil, table: nil, columns: [])
        }
        return AirmailBodyStore(queue: queue, table: table.name, columns: table.columns)
    }

    private static func pairedURL(_ messageFile: URL) -> URL {
        let name = messageFile.deletingPathExtension().lastPathComponent
        let bodyName = name.hasPrefix("Message") ? "Body" + name.dropFirst("Message".count) : name
        return messageFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Body", directoryHint: .isDirectory)
            .appending(path: bodyName)
            .appendingPathExtension("db")
    }

    private static func query(table: String, columns: Set<String>) -> String {
        var selected = ["CAST(plainbody AS BLOB) AS plainbody", "CAST(htmlbody AS BLOB) AS htmlbody"]
        if columns.contains("ezip") {
            selected.append("ezip")
        }
        return """
        SELECT \(selected.joined(separator: ", "))
        FROM \(AirmailSQLite.quote(table))
        WHERE idx = ?
        """
    }

    private static func text(from row: Row, columns: Set<String>) -> AirmailBodyText {
        let compressed = columns.contains("ezip") && ((row["ezip"] as Int64?) ?? 0) != 0
        return AirmailBodyText.rendered(
            plain: AirmailCompression.text(from: blob(row, "plainbody"), compressed: compressed),
            html: AirmailCompression.text(from: blob(row, "htmlbody"), compressed: compressed)
        )
    }

    private static func blob(_ row: Row, _ name: String) -> Data {
        let value: Data? = row[name]
        return value ?? Data()
    }
}

struct AirmailRFCStore {
    var queue: DatabaseQueue?
    var table: String?

    func data(idx: Int64) throws -> Data? {
        guard let queue, let table else { return nil }
        let sql = """
        SELECT CAST(rfc AS BLOB) AS rfc
        FROM \(AirmailSQLite.quote(table))
        WHERE idx = ?
        """
        return try queue.read { database in
            guard let row = try Row.fetchOne(database, sql: sql, arguments: [idx]) else { return nil }
            let value: Data? = row["rfc"]
            return value
        }
    }

    static func open(account: URL) throws -> AirmailRFCStore {
        let url = account.appending(path: "Rfc.db")
        guard let queue = try AirmailSQLite.openReadOnly(url) else {
            return AirmailRFCStore(queue: nil, table: nil)
        }
        let tables = try AirmailSQLite.tables(in: queue)
        guard let table = tables.first(where: { $0.columns.contains("rfc") && $0.columns.contains("idx") }) else {
            return AirmailRFCStore(queue: nil, table: nil)
        }
        return AirmailRFCStore(queue: queue, table: table.name)
    }
}
