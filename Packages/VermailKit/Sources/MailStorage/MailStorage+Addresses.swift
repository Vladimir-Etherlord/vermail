import Foundation
import GRDB

public extension MailDatabase {
    func recentAddresses(limit: Int = 100) throws -> [String] {
        let rows = try dbQueue.read { database in
            try Row.fetchAll(
                database,
                sql: """
                SELECT from_address, to_addresses
                FROM messages
                ORDER BY received_at DESC, id DESC
                LIMIT 400
                """
            )
        }

        var seen: Set<String> = []
        var result: [String] = []
        for row in rows {
            let fromAddress: String? = row["from_address"]
            let toRaw: String = row["to_addresses"]
            var candidates: [String] = []
            if let fromAddress {
                candidates.append(fromAddress)
            }
            candidates += toRaw.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            for candidate in candidates where !candidate.isEmpty {
                let key = candidate.lowercased()
                if seen.insert(key).inserted {
                    result.append(candidate)
                }
            }
        }
        return Array(result.prefix(limit))
    }
}
