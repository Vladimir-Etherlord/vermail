import Foundation
import MailCore
import MailStorage
import MIMEKit

enum MessageMetadataExtractor {
    static func makeStoredMessageInput(
        from rawData: Data,
        accountID: UUID,
        remoteUID: String,
        folder: MailFolderKind = .inbox
    ) -> StoredMessageInput {
        let parsed = try? MIME.parse(rawData)
        let headers = parsed?.headers ?? []

        let fromAddress = headerValue("From", in: headers)
        let toHeader = headerValue("To", in: headers) ?? ""
        let toAddresses = splitAddressList(toHeader)
        let receivedAt = headerValue("Date", in: headers).flatMap(parseRFC5322Date) ?? Date()
        let snippet = makeSnippet(plainBody: parsed?.plainBody, htmlBody: parsed?.htmlBody)
        let hasAttachments = !(parsed?.attachments.isEmpty ?? true)

        return StoredMessageInput(
            accountID: accountID,
            remoteUID: remoteUID,
            folder: folder,
            subject: parsed?.subject,
            fromAddress: fromAddress,
            toAddresses: toAddresses,
            snippet: snippet,
            receivedAt: receivedAt,
            isRead: false,
            hasAttachments: hasAttachments,
            rawSource: rawData
        )
    }

    static func headerValue(_ name: String, in headers: [MIMEHeader]) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    static func splitAddressList(_ raw: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false

        for character in raw {
            if character == "\"" {
                inQuotes.toggle()
                current.append(character)
            } else if character == ",", !inQuotes {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    result.append(trimmed)
                }
                current = ""
            } else {
                current.append(character)
            }
        }

        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            result.append(trimmed)
        }
        return result
    }

    static func parseRFC5322Date(_ raw: String) -> Date? {
        let cleaned = raw
            .replacingOccurrences(of: #"\s*\([^)]*\)\s*"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let formats = [
            "EEE, d MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm:ss z",
            "d MMM yyyy HH:mm:ss Z",
            "d MMM yyyy HH:mm:ss z",
            "EEE, d MMM yyyy HH:mm Z",
            "d MMM yyyy HH:mm Z",
            "EEE, d MMM yy HH:mm:ss Z",
            "d MMM yy HH:mm:ss Z",
        ]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: cleaned) {
                return date
            }
        }
        return nil
    }

    static func makeSnippet(plainBody: String?, htmlBody: String?, maxLength: Int = 200) -> String? {
        let rawText: String
        if let plainBody, !plainBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rawText = plainBody
        } else if let htmlBody, !htmlBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rawText = removingTags(htmlBody)
        } else {
            return nil
        }

        let collapsed = previewText(rawText)
        guard !collapsed.isEmpty else { return nil }
        if collapsed.count <= maxLength {
            return collapsed
        }
        return String(collapsed.prefix(maxLength)) + "…"
    }

    /// List preview. Mailers pad the preheader with `&zwnj;` and blank characters; that padding is not text.
    static func previewText(_ text: String) -> String {
        let decoded = decodeHTMLEntities(text)
        let visible = removingInvisibleCharacters(cuttingPreviewPadding(decoded))
        return visible
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func stripHTML(_ html: String) -> String {
        removingInvisibleCharacters(decodeHTMLEntities(removingTags(html)))
    }

    private static func removingTags(_ html: String) -> String {
        var text = html
        text = text.replacingOccurrences(
            of: #"(?is)<(script|style)[^>]*>.*?</\1>"#,
            with: " ",
            options: .regularExpression
        )
        return text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
    }
}
