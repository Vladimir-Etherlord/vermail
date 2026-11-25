import Foundation
import GRDB

struct AirmailMessageRecord {
    var idx: Int64
    var messageID: String?
    var subject: String
    var folderBlob: Data
    var sender: Data
    var sentAt: Int64?
    var receivedAt: Int64?
    var to: Data
    var cc: Data
    var bcc: Data
    var attachmentCount: Int
    var excerpt: String?
    var flag: Int64?
    var inlineRFC: Data?
    var externalAttachments: Data
    var inlineAttachments: Data
}

enum AirmailMessageSQL {
    static func query(table: AirmailTable) -> String {
        var selected = ["idx"]
        if !table.columns.contains("idx") {
            selected = ["rowid AS idx"]
        }
        let blobs = [
            "uidfolderid", "senderaddr", "tox", "ccx", "bccx", "rfc",
            "attachmentsexternal", "attachmentsinternal",
        ]
        for name in blobs where table.columns.contains(name) {
            selected.append("CAST(\(name) AS BLOB) AS \(name)")
        }
        for name in ["messageid", "subject", "excerpt"] where table.columns.contains(name) {
            selected.append(name)
        }
        for name in ["senderdate", "rcvdate", "attachmentscount", "flagx"] where table.columns.contains(name) {
            selected.append(name)
        }
        return "SELECT \(selected.joined(separator: ", ")) FROM \(AirmailSQLite.quote(table.name))"
    }

    static func record(from row: Row) -> AirmailMessageRecord {
        AirmailMessageRecord(
            idx: row["idx"] ?? 0,
            messageID: text(row, "messageid"),
            subject: text(row, "subject") ?? "",
            folderBlob: blob(row, "uidfolderid"),
            sender: blob(row, "senderaddr"),
            sentAt: integer(row, "senderdate"),
            receivedAt: integer(row, "rcvdate"),
            to: blob(row, "tox"),
            cc: blob(row, "ccx"),
            bcc: blob(row, "bccx"),
            attachmentCount: Int(integer(row, "attachmentscount") ?? 0),
            excerpt: text(row, "excerpt"),
            flag: has(row, "flagx") ? integer(row, "flagx") : nil,
            inlineRFC: has(row, "rfc") ? blob(row, "rfc") : nil,
            externalAttachments: blob(row, "attachmentsexternal"),
            inlineAttachments: blob(row, "attachmentsinternal")
        )
    }

    private static func has(_ row: Row, _ name: String) -> Bool {
        row.columnNames.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    private static func text(_ row: Row, _ name: String) -> String? {
        guard has(row, name) else { return nil }
        let value: String? = row[name]
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func blob(_ row: Row, _ name: String) -> Data {
        guard has(row, name) else { return Data() }
        let value: Data? = row[name]
        return value ?? Data()
    }

    private static func integer(_ row: Row, _ name: String) -> Int64? {
        guard has(row, name) else { return nil }
        return row[name]
    }
}
