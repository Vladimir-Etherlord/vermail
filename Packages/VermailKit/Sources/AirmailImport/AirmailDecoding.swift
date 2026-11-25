import Foundation
import MailCore

enum AirmailFolders {
    static func kind(named name: String) -> MailFolderKind? {
        let key = normalized(name)
        if let exact = exact[key] {
            return exact
        }
        return containedKind(key)
    }

    static func isVirtual(_ name: String) -> Bool {
        let key = normalized(name)
        if key.hasPrefix("[airmail]") {
            return true
        }
        return virtualNames.contains(key)
    }

    static func choose(names: [String]) -> MailFolderKind {
        let real = names.filter { !isVirtual($0) }
        let kinds = Set(real.compactMap { kind(named: $0) })
        let order: [MailFolderKind] = [.trash, .spam, .drafts, .sent, .inbox, .archive]
        if let match = order.first(where: { kinds.contains($0) }) {
            return match
        }
        return real.isEmpty ? .inbox : .archive
    }

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func containedKind(_ key: String) -> MailFolderKind? {
        let pairs: [(String, MailFolderKind)] = [
            ("inbox", .inbox), ("входящ", .inbox),
            ("отправ", .sent), ("sent", .sent),
            ("чернов", .drafts), ("draft", .drafts),
            ("корзин", .trash), ("trash", .trash), ("deleted", .trash),
            ("спам", .spam), ("spam", .spam), ("junk", .spam),
            ("архив", .archive), ("archive", .archive),
        ]
        return pairs.first { key.contains($0.0) }?.1
    }

    private static let virtualNames: Set<String> = [
        "all mail", "вся почта", "search", "поиск", "starred", "important", "flagged",
    ]

    private static let exact: [String: MailFolderKind] = [
        "inbox": .inbox,
        "входящие": .inbox,
        "sent": .sent,
        "sent items": .sent,
        "sent messages": .sent,
        "отправленные": .sent,
        "drafts": .drafts,
        "draft": .drafts,
        "черновики": .drafts,
        "trash": .trash,
        "deleted": .trash,
        "deleted items": .trash,
        "deleted messages": .trash,
        "bin": .trash,
        "корзина": .trash,
        "spam": .spam,
        "junk": .spam,
        "junk mail": .spam,
        "спам": .spam,
        "archive": .archive,
        "archives": .archive,
        "архив": .archive,
    ]
}

enum AirmailDates {
    /// Unix time of 2001-01-01. Airmail stores seconds since 1970. Anything at or after this
    /// instant is a Unix timestamp; smaller values are Apple's 2001 reference date.
    private static let unixCutoff: Int64 = 978_307_200

    static func date(from raw: Int64?) -> Date? {
        guard let raw, raw > 0 else { return nil }
        if raw > 10_000_000_000_000 {
            return Date(timeIntervalSince1970: Double(raw) / 1_000_000)
        }
        if raw > 10_000_000_000 {
            return Date(timeIntervalSince1970: Double(raw) / 1000)
        }
        if raw >= unixCutoff {
            return Date(timeIntervalSince1970: Double(raw))
        }
        return Date(timeIntervalSinceReferenceDate: Double(raw))
    }
}

enum AirmailFlags {
    /// Bit 0 is the IMAP `\Seen` flag. Historical mail without a flag stays read.
    static func isRead(_ flag: Int64?) -> Bool {
        guard let flag else { return true }
        return (flag & 1) != 0
    }
}

enum AirmailAddresses {
    static func display(from data: Data) -> String {
        let text = cleaned(data)
        if let angled = angledAddress(in: text) {
            return angled
        }
        return emails(in: text).first ?? ""
    }

    static func emails(in data: Data) -> [String] {
        emails(in: cleaned(data))
    }

    static func emails(in text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: emailPattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<String>()
        var ordered: [String] = []
        for match in expression.matches(in: text, range: range) {
            guard let swiftRange = Range(match.range, in: text) else { continue }
            let email = String(text[swiftRange])
            if seen.insert(email.lowercased()).inserted {
                ordered.append(email)
            }
        }
        return ordered
    }

    private static let emailPattern = "[A-Z0-9._%+\\-]+@[A-Z0-9.\\-]+\\.[A-Z]{2,}"

    private static func cleaned(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\u{0}", with: " ")
    }

    private static func angledAddress(in text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: #"<[^>\s]+@[^>\s]+>"#) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = expression.firstMatch(in: text, range: range),
              let emailRange = Range(match.range, in: text)
        else {
            return nil
        }
        let name = displayName(before: emailRange.lowerBound, in: text)
        if name.isEmpty {
            return String(text[emailRange])
        }
        return "\(name) \(text[emailRange])"
    }

    private static func displayName(before end: String.Index, in text: String) -> String {
        var start = end
        var walked = 0
        while start > text.startIndex, walked < 80 {
            let previous = text.index(before: start)
            guard let scalar = text[previous].unicodeScalars.first, isNameCharacter(scalar) else { break }
            start = previous
            walked += 1
        }
        return String(text[start ..< end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isNameCharacter(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value >= 32 && scalar != "<" && scalar != "\u{FFFD}"
    }
}

enum AirmailMessageID {
    static let remotePrefix = "airmail:"

    static func remoteUID(shard: String, idx: Int64) -> String {
        "\(remotePrefix)\(shard):\(idx)"
    }

    static func normalize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            .lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    static func headerValue(in data: Data) -> String? {
        let text = String(data: Data(data.prefix(65536)), encoding: .isoLatin1) ?? ""
        let header = headerBlock(text)
        return normalize(field("message-id", in: header))
    }

    private static func headerBlock(_ text: String) -> String {
        if let range = text.range(of: "\r\n\r\n") {
            return String(text[..<range.lowerBound])
        }
        if let range = text.range(of: "\n\n") {
            return String(text[..<range.lowerBound])
        }
        return text
    }

    private static func field(_ name: String, in header: String) -> String? {
        let lines = header.replacingOccurrences(of: "\r\n", with: "\n").split(
            separator: "\n",
            omittingEmptySubsequences: false
        )
        var current: String?
        for lineSub in lines {
            let line = String(lineSub)
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                current? += " " + line.trimmingCharacters(in: .whitespaces)
                continue
            }
            if let current, current.lowercased().hasPrefix(name + ":") {
                return String(current.drop(while: { $0 != ":" }).dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            current = line
        }
        guard let current, current.lowercased().hasPrefix(name + ":") else { return nil }
        return String(current.drop(while: { $0 != ":" }).dropFirst()).trimmingCharacters(in: .whitespaces)
    }
}
