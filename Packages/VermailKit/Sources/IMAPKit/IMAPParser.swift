import Foundation
import MailCore

struct IMAPLine: Equatable, Sendable {
    var text: String
    var literal: Data?
}

struct IMAPReply: Equatable, Sendable {
    var lines: [IMAPLine]
    var statusText: String
}

struct IMAPListEntry: Equatable, Sendable {
    var attributes: [String]
    var rawName: String
}

struct IMAPFetchedMessage: Equatable, Sendable {
    var uid: String
    var size: Int
    var isRead: Bool
    var body: Data?
}

struct IMAPMessageKey: Equatable, Sendable {
    var mailbox: String
    var uidValidity: String
    var uid: String

    var storageValue: String {
        "\(mailbox)\u{1}\(uidValidity)\u{1}\(uid)"
    }

    static func parse(_ value: String) -> IMAPMessageKey? {
        let parts = value.split(separator: "\u{1}", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, !parts[0].isEmpty, !parts[2].isEmpty else { return nil }
        return IMAPMessageKey(mailbox: parts[0], uidValidity: parts[1], uid: parts[2])
    }
}

enum IMAPParser {
    static func literalLength(atEndOf line: String) -> Int? {
        guard let open = line.lastIndex(of: "{"), line.hasSuffix("}") else { return nil }
        let inside = line[line.index(after: open) ..< line.index(before: line.endIndex)]
        let digits = inside.hasSuffix("+") ? inside.dropLast() : inside
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }
        return Int(digits)
    }

    static func quote(_ value: String) -> String {
        var escaped = ""
        for character in value {
            if character == "\\" || character == "\"" {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return "\"\(escaped)\""
    }

    static func isQuotedSafe(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value <= 0x7E }
    }

    static func canonicalMailbox(_ rawName: String) -> String {
        let decoded = IMAPUTF7.decode(rawName)
        if decoded.caseInsensitiveCompare("INBOX") == .orderedSame {
            return "INBOX"
        }
        return rawName
    }

    static func uidValidity(in text: String) -> String? {
        let upper = text.uppercased()
        guard let range = upper.range(of: "UIDVALIDITY") else { return nil }
        var index = range.upperBound
        while index < text.endIndex, !text[index].isNumber {
            index = text.index(after: index)
        }
        var digits = ""
        while index < text.endIndex, text[index].isNumber {
            digits.append(text[index])
            index = text.index(after: index)
        }
        return digits.isEmpty ? nil : digits
    }

    static func isSeen(_ text: String) -> Bool {
        let upper = text.uppercased()
        guard let flags = upper.range(of: "FLAGS") else { return false }
        let rest = upper[flags.upperBound...]
        guard let open = rest.firstIndex(of: "("), let close = rest[open...].firstIndex(of: ")") else {
            return false
        }
        let inside = rest[rest.index(after: open) ..< close]
        return inside.split(separator: " ").contains { $0 == "\\SEEN" }
    }

    static func listEntry(text: String, literal: Data?) -> IMAPListEntry? {
        guard text.uppercased().hasPrefix("* LIST "), let open = text.firstIndex(of: "("),
              let close = text[open...].firstIndex(of: ")")
        else {
            return nil
        }
        let attributeText = text[text.index(after: open) ..< close]
        let attributes = attributeText.split(separator: " ").map(String.init)
        let rawName = mailboxName(text: text, close: close, literal: literal)
        guard let rawName, !rawName.isEmpty else { return nil }
        return IMAPListEntry(attributes: attributes, rawName: rawName)
    }

    static func mailboxes(from lines: [IMAPLine]) -> [RemoteMailbox] {
        var chosen: [MailFolderKind: (name: String, special: Bool)] = [:]
        for line in lines {
            guard let entry = listEntry(text: line.text, literal: line.literal), let folder = mailboxFolder(
                attributes: entry.attributes,
                rawName: entry.rawName
            ) else { continue }
            let special = hasSpecialUse(entry.attributes)
            if let existing = chosen[folder], existing.special || !special {
                continue
            }
            chosen[folder] = (canonicalMailbox(entry.rawName), special)
        }
        if chosen[.inbox] == nil {
            chosen[.inbox] = ("INBOX", true)
        }
        return MailFolderKind.allCases.compactMap { folder in
            guard let name = chosen[folder]?.name else { return nil }
            return RemoteMailbox(name: name, folder: folder)
        }
    }

    static func mailboxFolder(attributes: [String], rawName: String) -> MailFolderKind? {
        let flags = Set(attributes.map { $0.uppercased() })
        if flags.contains("\\NOSELECT") || flags.contains("\\ALL") {
            return nil
        }
        if let special = IMAPFolderNames.specialUse.first(where: { flags.contains($0.key) })?.value {
            return special
        }
        let decoded = IMAPUTF7.decode(rawName).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if decoded == "inbox" {
            return .inbox
        }
        return IMAPFolderNames.byName[decoded]
    }

    static func fetchRecords(from lines: [IMAPLine]) -> [IMAPFetchedMessage] {
        lines.compactMap { line in
            guard line.text.uppercased().contains("FETCH"), let uid = token(after: "UID", in: line.text),
                  Int(uid) != nil else { return nil }
            let size = token(after: "RFC822.SIZE", in: line.text).flatMap(Int.init) ?? 0
            return IMAPFetchedMessage(uid: uid, size: size, isRead: isSeen(line.text), body: line.literal)
        }
    }

    static func token(after label: String, in text: String) -> String? {
        let upper = text.uppercased()
        let needle = label.uppercased()
        var search = upper.startIndex
        while let range = upper.range(of: needle, range: search ..< upper.endIndex) {
            let beforeIsBoundary = range.lowerBound == upper.startIndex
                || !upper[upper.index(before: range.lowerBound)].isLetter
            let after = range.upperBound
            let afterIsBoundary = after == upper.endIndex || !upper[after].isLetter
            if beforeIsBoundary, afterIsBoundary {
                return readToken(in: text, from: after)
            }
            search = range.upperBound
        }
        return nil
    }

    private static func hasSpecialUse(_ attributes: [String]) -> Bool {
        let flags = Set(attributes.map { $0.uppercased() })
        return IMAPFolderNames.specialUse.keys.contains { flags.contains($0) }
    }

    private static func mailboxName(text: String, close: String.Index, literal: Data?) -> String? {
        if let literal, !literal.isEmpty {
            return String(decoding: literal, as: UTF8.self)
        }
        let rest = text[text.index(after: close)...].trimmingCharacters(in: .whitespaces)
        guard let separator = rest.firstIndex(of: " ") else { return nil }
        let name = rest[rest.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        return unquote(String(name))
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return value }
        var result = ""
        var escaped = false
        for character in value.dropFirst().dropLast() {
            if escaped {
                result.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                result.append(character)
            }
        }
        return result
    }

    private static func readToken(in text: String, from start: String.Index) -> String? {
        var index = start
        while index < text.endIndex, text[index] == " " {
            index = text.index(after: index)
        }
        var token = ""
        while index < text.endIndex {
            let character = text[index]
            if character == " " || character == ")" {
                break
            }
            token.append(character)
            index = text.index(after: index)
        }
        return token.isEmpty ? nil : token
    }
}

private enum IMAPFolderNames {
    static let specialUse: [String: MailFolderKind] = [
        "\\INBOX": .inbox,
        "\\SENT": .sent,
        "\\DRAFTS": .drafts,
        "\\TRASH": .trash,
        "\\JUNK": .spam,
        "\\SPAM": .spam,
        "\\ARCHIVE": .archive,
    ]

    static let byName: [String: MailFolderKind] = [
        "sent": .sent,
        "sent items": .sent,
        "sent messages": .sent,
        "sent mail": .sent,
        "отправленные": .sent,
        "drafts": .drafts,
        "draft": .drafts,
        "черновики": .drafts,
        "trash": .trash,
        "bin": .trash,
        "deleted": .trash,
        "deleted items": .trash,
        "deleted messages": .trash,
        "корзина": .trash,
        "удаленные": .trash,
        "удалённые": .trash,
        "junk": .spam,
        "junk mail": .spam,
        "spam": .spam,
        "спам": .spam,
        "archive": .archive,
        "archives": .archive,
        "архив": .archive,
    ]
}
