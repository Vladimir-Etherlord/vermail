import Foundation
import GRDB

public extension MailDatabase {
    func messageIDsWithEncodedWords() throws -> [Int64] {
        try dbQueue.read { database in
            try Int64.fetchAll(
                database,
                sql: """
                SELECT id FROM messages
                WHERE instr(ifnull(subject, ''), '=?') > 0
                   OR instr(ifnull(from_address, ''), '=?') > 0
                   OR instr(ifnull(to_addresses, ''), '=?') > 0
                   OR instr(ifnull(snippet, ''), '&zwnj;') > 0
                   OR instr(ifnull(snippet, ''), '&zwj;') > 0
                   OR instr(ifnull(snippet, ''), '&nbsp;') > 0
                   OR instr(ifnull(snippet, ''), '&#') > 0
                   OR instr(ifnull(snippet, ''), char(10240)) > 0
                ORDER BY id
                """
            )
        }
    }

    func updateDecodedHeaders(
        id: Int64,
        subject: String?,
        fromAddress: String?,
        toAddresses: [String],
        snippet: String?
    ) throws {
        try dbQueue.write { database in
            try database.execute(
                sql: """
                UPDATE messages
                SET subject = ?, from_address = ?, to_addresses = ?, snippet = ?, updated_at = ?
                WHERE id = ?
                """,
                arguments: [
                    subject,
                    fromAddress,
                    toAddresses.joined(separator: ","),
                    snippet,
                    Date(),
                    id,
                ]
            )
        }
    }
}
