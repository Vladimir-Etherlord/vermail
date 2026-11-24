import Foundation

struct MIMEParsedContentType {
    let mediaType: String
    let parameters: [String: String]
}

struct MIMEContinuationFragment {
    let index: Int
    let value: String
    let isEncoded: Bool
}

enum MIMECodec {
    static func headerValue(_ headers: [MIMEHeader], _ name: String) -> String? {
        headers.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.value
    }

    static func parseContentType(_ raw: String) -> MIMEParsedContentType {
        let segments = raw.split(separator: ";", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        let mediaType = (segments.first ?? "text/plain").lowercased()

        var parameters: [String: String] = [:]
        var continued: [String: [MIMEContinuationFragment]] = [:]

        for segment in segments.dropFirst() {
            guard let equalIndex = segment.firstIndex(of: "=") else { continue }
            let keyRaw = String(segment[..<equalIndex]).trimmingCharacters(in: .whitespaces).lowercased()
            var value = String(segment[segment.index(after: equalIndex)...]).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }

            if let continuation = parseContinuationKey(keyRaw) {
                continued[continuation.base, default: []].append(continuation.fragment(value))
                continue
            }

            if keyRaw.hasSuffix("*") {
                parameters[String(keyRaw.dropLast())] = decodeRFC2231(value)
            } else {
                parameters[keyRaw] = decodeRFC2047(value)
            }
        }

        for (base, fragments) in continued {
            let sorted = fragments.sorted { $0.index < $1.index }
            let joined = sorted.map(\.value).joined()
            let isEncoded = sorted.contains(where: \.isEncoded)
            parameters[base] = isEncoded ? decodeRFC2231(joined) : decodeRFC2047(joined)
        }

        return MIMEParsedContentType(mediaType: mediaType, parameters: parameters)
    }

    static func parseContinuationKey(_ key: String) -> (base: String, fragment: (String) -> MIMEContinuationFragment)? {
        let pattern = /^([a-z0-9._-]+)\*(\d+)(\*)?$/
        guard let match = key.wholeMatch(of: pattern), let index = Int(match.2) else {
            return nil
        }
        let base = String(match.1)
        let encoded = match.3 != nil
        return (base: base, fragment: { value in
            MIMEContinuationFragment(index: index, value: value, isEncoded: encoded)
        })
    }

    static func decodeTransferEncoding(_ encoding: String?, body: Data) -> Data {
        switch encoding?.lowercased() {
        case "base64":
            let compact = String(decoding: body, as: UTF8.self)
                .replacingOccurrences(of: "\r", with: "")
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\t", with: "")
                .replacingOccurrences(of: " ", with: "")
            return Data(base64Encoded: compact) ?? body
        case "quoted-printable":
            return decodeQuotedPrintable(body)
        default:
            return body
        }
    }

    static func decodeQuotedPrintable(_ data: Data) -> Data {
        let bytes = Array(data)
        var out: [UInt8] = []
        var index = 0

        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x3D {
                if index + 1 < bytes.count, bytes[index + 1] == 0x0A {
                    index += 2
                    continue
                }
                if index + 2 < bytes.count, bytes[index + 1] == 0x0D, bytes[index + 2] == 0x0A {
                    index += 3
                    continue
                }
                if index + 2 < bytes.count,
                   let first = hexValue(bytes[index + 1]),
                   let second = hexValue(bytes[index + 2])
                {
                    out.append((first << 4) | second)
                    index += 3
                    continue
                }
            }
            out.append(byte)
            index += 1
        }

        return Data(out)
    }

    static func encodeQuotedPrintable(_ data: Data) -> String {
        var out = ""
        for byte in data {
            if byte == 0x0D {
                continue
            }
            if byte == 0x0A {
                out += MIME.lineBreak
                continue
            }
            if byte == 0x09 || byte == 0x20 || (byte >= 0x21 && byte <= 0x7E && byte != 0x3D) {
                out += String(UnicodeScalar(byte))
            } else {
                out += String(format: "=%02X", byte)
            }
        }
        return out
    }

    static func decodeText(_ data: Data, charset: String?) -> String {
        if let charset, let decoded = decodeBytes(data, charset: charset) {
            return decoded
        }
        return String(data: data, encoding: .utf8) ??
            String(data: data, encoding: .windowsCP1251) ??
            String(data: data, encoding: .isoLatin1) ??
            String(decoding: data, as: UTF8.self)
    }

    static func decodeRFC2047(_ value: String) -> String {
        let normalized = normalizeRFC2047Separators(in: value)
        return decodeRFC2047Strict(normalized)
            .replacingOccurrences(of: "\r\n", with: "")
            .replacingOccurrences(of: "\n", with: "")
    }

    private static func decodeRFC2047Strict(_ value: String) -> String {
        let pattern = #"=\?([^?]+)\?([bBqQ])\?([^?]+)\?="#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }

        let nsValue = value as NSString
        let matches = regex.matches(in: value, range: NSRange(location: 0, length: nsValue.length))
        guard !matches.isEmpty else { return value }

        var result = ""
        var cursor = 0

        for match in matches {
            let fullRange = match.range(at: 0)
            appendFoldingGap(from: nsValue, start: cursor, end: fullRange.location, into: &result)
            result += decodedEncodedWord(nsValue, match) ?? nsValue.substring(with: fullRange)
            cursor = fullRange.location + fullRange.length
        }

        if cursor < nsValue.length {
            result += nsValue.substring(from: cursor)
        }

        return result
    }

    /// Some senders collapse adjacent encoded-words into `?==?charset?...?=`.
    /// Treat this as `?= =?charset?...?=` to decode the header anyway.
    private static func normalizeRFC2047Separators(in value: String) -> String {
        var normalized = value
        while normalized.contains("?==?") {
            normalized = normalized.replacingOccurrences(of: "?==?", with: "?= =?")
        }
        return normalized
    }

    static func encodeRFC2047IfNeeded(_ text: String) -> String {
        guard !text.unicodeScalars.allSatisfy(\.isASCII) else {
            return text
        }
        return "=?UTF-8?B?\(Data(text.utf8).base64EncodedString())?="
    }

    static func decodeRFC2231(_ value: String) -> String {
        let unquoted: String = if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            String(value.dropFirst().dropLast())
        } else {
            value
        }

        let pieces = unquoted.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
        if pieces.count == 3 {
            let charset = String(pieces[0])
            let encoded = String(pieces[2])
            let bytes = percentDecodedBytes(encoded)
            return decodeBytes(bytes, charset: charset) ?? encoded
        }

        if unquoted.contains("%") {
            let bytes = percentDecodedBytes(unquoted)
            return String(data: bytes, encoding: .utf8) ?? String(decoding: bytes, as: UTF8.self)
        }

        return decodeRFC2047(unquoted)
    }

    static func encodeRFC2231Value(_ value: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$&+-.^_`|~".utf8)
        let encoded = Data(value.utf8).map { byte -> String in
            if allowed.contains(byte) {
                return String(UnicodeScalar(byte))
            }
            return String(format: "%%%02X", byte)
        }.joined()
        return "utf-8''\(encoded)"
    }

    static func decodeBytes(_ data: Data, charset: String) -> String? {
        let iana = charset.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let aliases: [String: String] = [
            "cp1251": "windows-1251",
            "x-cp1251": "windows-1251",
            "koi8r": "koi8-r",
        ]
        let canonical = aliases[iana] ?? iana

        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(canonical as CFString)
        if cfEncoding != kCFStringEncodingInvalidId {
            let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
            return String(data: data, encoding: String.Encoding(rawValue: nsEncoding))
        }

        switch canonical {
        case "windows-1251":
            return String(data: data, encoding: .windowsCP1251)
        case "utf-8", "utf8":
            return String(data: data, encoding: .utf8)
        default:
            return nil
        }
    }

    static func percentDecodedBytes(_ text: String) -> Data {
        var out: [UInt8] = []
        let bytes = Array(text.utf8)
        var index = 0
        while index < bytes.count {
            if bytes[index] == 0x25,
               index + 2 < bytes.count,
               let first = hexValue(bytes[index + 1]),
               let second = hexValue(bytes[index + 2])
            {
                out.append((first << 4) | second)
                index += 3
            } else {
                out.append(bytes[index])
                index += 1
            }
        }
        return Data(out)
    }

    static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48 ... 57:
            byte - 48
        case 65 ... 70:
            byte - 55
        case 97 ... 102:
            byte - 87
        default:
            nil
        }
    }
}
