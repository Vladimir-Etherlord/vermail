import Foundation
import MIMEKit

enum AirmailRFC {
    static func message(
        plain: String,
        html: String,
        headers: AirmailRFCHeaders,
        files: [AirmailStoredFile] = []
    ) -> Data {
        let boundary = "vermail_boundary_\(headers.idx)"
        let rendered = withFiles(
            render(plain: plain, html: html, boundary: boundary),
            files: files,
            idx: headers.idx
        )
        var lines = headerLines(headers)
        lines.append("MIME-Version: 1.0")
        lines.append(contentsOf: rendered.headers)
        let text = lines.joined(separator: "\r\n") + "\r\n\r\n" + rendered.body
        return Data(text.utf8)
    }

    static func mailSource(from data: Data?) -> Data? {
        guard let data, !data.isEmpty else { return nil }
        if isGzip(data), let inflated = AirmailCompression.decompress(data), isMailSource(inflated) {
            return inflated
        }
        if isMailSource(data) {
            return data
        }
        return decodedBase64Source(data)
    }

    static func hasAttachment(_ data: Data) -> Bool {
        let text = String(data: data, encoding: .isoLatin1)?.lowercased() ?? ""
        return text.contains("content-disposition: attachment") || text.contains("content-disposition:attachment")
    }

    static func snippet(excerpt: String?, plain: String?) -> String? {
        let source = [excerpt, plain].compactMap(\.self).first { !$0.isEmpty }
        guard let source else { return nil }
        let collapsed = source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        if collapsed.count <= 200 {
            return collapsed
        }
        return String(collapsed.prefix(200))
    }

    static func readable(_ value: String) -> String {
        let single = value.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        guard single.contains("=?") else { return single }
        let raw = Data("Subject: \(single)\r\n\r\n".utf8)
        return (try? MIME.parse(raw))?.subject ?? single
    }

    private static func isGzip(_ data: Data) -> Bool {
        AirmailCompression.isGzip(data)
    }

    private static func isMailSource(_ data: Data) -> Bool {
        let head = String(data: Data(data.prefix(4096)), encoding: .isoLatin1)?.lowercased() ?? ""
        let markers = ["from:", "received:", "return-path:", "message-id:", "subject:", "mime-version:"]
        if markers.contains(where: { head.hasPrefix($0) }) {
            return true
        }
        return markers.contains { head.contains("\n" + $0) }
    }

    private static func decodedBase64Source(_ data: Data) -> Data? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let compact = text.filter { !$0.isWhitespace }
        guard let decoded = Data(base64Encoded: compact), isMailSource(decoded) else { return nil }
        return decoded
    }

    private static func headerLines(_ headers: AirmailRFCHeaders) -> [String] {
        var lines: [String] = []
        if let date = headers.date {
            lines.append("Date: \(dateHeader(date))")
        }
        lines.append("From: \(encoded(headers.from))")
        if let to = addressList(headers.to) {
            lines.append("To: \(to)")
        }
        if let cc = addressList(headers.cc) {
            lines.append("Cc: \(cc)")
        }
        lines.append("Message-ID: <\(headers.messageID)>")
        lines.append("Subject: \(encoded(headers.subject))")
        return lines
    }

    private static func render(plain: String, html: String, boundary: String) -> (headers: [String], body: String) {
        if !plain.isEmpty, !html.isEmpty {
            return multipart(plain: plain, html: html, boundary: boundary)
        }
        if !html.isEmpty {
            return single(html, contentType: "text/html")
        }
        return single(plain, contentType: "text/plain")
    }

    private static func single(_ text: String, contentType: String) -> (headers: [String], body: String) {
        (
            [
                "Content-Type: \(contentType); charset=utf-8",
                "Content-Transfer-Encoding: base64",
            ],
            wrappedBase64(Data(text.utf8))
        )
    }

    private static func multipart(plain: String, html: String, boundary: String) -> (headers: [String], body: String) {
        let body = [
            "--\(boundary)",
            "Content-Type: text/plain; charset=utf-8",
            "Content-Transfer-Encoding: base64",
            "",
            wrappedBase64(Data(plain.utf8)),
            "--\(boundary)",
            "Content-Type: text/html; charset=utf-8",
            "Content-Transfer-Encoding: base64",
            "",
            wrappedBase64(Data(html.utf8)),
            "--\(boundary)--",
            "",
        ].joined(separator: "\r\n")
        return (
            [
                "Content-Type: multipart/alternative; boundary=\"\(boundary)\"",
            ],
            body
        )
    }

    private static func withFiles(
        _ inner: (headers: [String], body: String),
        files: [AirmailStoredFile],
        idx: Int64
    ) -> (headers: [String], body: String) {
        guard !files.isEmpty else { return inner }
        let boundary = "vermail_files_\(idx)"
        let parts = [bounded(inner.headers, body: inner.body, boundary: boundary)]
            + files.map { bounded(fileHeaders($0), body: wrappedBase64($0.data), boundary: boundary) }
        return (
            ["Content-Type: multipart/mixed; boundary=\"\(boundary)\""],
            parts.joined() + "--\(boundary)--\r\n"
        )
    }

    private static func bounded(_ headers: [String], body: String, boundary: String) -> String {
        (["--\(boundary)"] + headers + ["", body]).joined(separator: "\r\n") + "\r\n"
    }

    private static func encodedFilename(_ value: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$&+-.^_`|~".utf8)
        let encoded = value.utf8.map { byte -> String in
            guard allowed.contains(byte), let scalar = UnicodeScalar(UInt32(byte)) else {
                return String(format: "%%%02X", byte)
            }
            return String(scalar)
        }.joined()
        return "utf-8''\(encoded)"
    }

    private static func fileHeaders(_ file: AirmailStoredFile) -> [String] {
        let name = encodedFilename(file.filename)
        return [
            "Content-Type: \(file.mimeType); name*=\(name)",
            "Content-Disposition: attachment; filename*=\(name)",
            "Content-Transfer-Encoding: base64",
        ]
    }

    private static func addressList(_ values: [String]) -> String? {
        let cleaned = values.map { encoded($0) }.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }
        return cleaned.joined(separator: ", ")
    }

    private static func encoded(_ value: String) -> String {
        let flat = value.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        guard flat.unicodeScalars.contains(where: { !$0.isASCII }) else { return flat }
        return encodedWords(flat)
    }

    private static func encodedWords(_ value: String) -> String {
        let bytes = Array(value.utf8)
        var words: [String] = []
        var index = 0
        while index < bytes.count {
            let end = min(index + 45, bytes.count)
            let piece = Data(bytes[index ..< end]).base64EncodedString()
            words.append("=?UTF-8?B?\(piece)?=")
            index = end
        }
        return words.joined(separator: "\r\n ")
    }

    private static func wrappedBase64(_ data: Data) -> String {
        let encoded = data.base64EncodedString()
        var lines: [String] = []
        var index = encoded.startIndex
        while index < encoded.endIndex {
            let end = encoded.index(index, offsetBy: 76, limitedBy: encoded.endIndex) ?? encoded.endIndex
            lines.append(String(encoded[index ..< end]))
            index = end
        }
        return lines.joined(separator: "\r\n")
    }

    private static func dateHeader(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.string(from: date)
    }
}

struct AirmailRFCHeaders {
    var idx: Int64
    var date: Date?
    var from: String
    var to: [String]
    var cc: [String]
    var messageID: String
    var subject: String
}
