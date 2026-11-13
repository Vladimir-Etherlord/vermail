import Foundation

extension MIMECodec {
    static func appendFoldingGap(
        from value: NSString,
        start: Int,
        end: Int,
        into result: inout String
    ) {
        guard end > start else { return }
        let gap = value.substring(with: NSRange(location: start, length: end - start))
        // RFC 2047: linear whitespace between adjacent encoded-words is not significant.
        if start > 0, gap.unicodeScalars.allSatisfy(isFoldingWhitespace) {
            return
        }
        result += gap
    }

    static func decodedEncodedWord(_ value: NSString, _ match: NSTextCheckingResult) -> String? {
        let charset = value.substring(with: match.range(at: 1))
        let encoding = value.substring(with: match.range(at: 2)).lowercased()
        let payload = value.substring(with: match.range(at: 3))
        guard let bytes = encodedWordBytes(encoding: encoding, payload: payload) else { return nil }
        return decodeBytes(bytes, charset: charset)
    }

    /// Header unfolding inserts a space inside a folded encoded-word. Strip it before decoding.
    static func encodedWordBytes(encoding: String, payload: String) -> Data? {
        let compact = String(payload.unicodeScalars.filter { !isFoldingWhitespace($0) })
        if encoding == "b" {
            return Data(base64Encoded: paddedBase64(compact), options: .ignoreUnknownCharacters)
        }
        let normalized = compact.replacingOccurrences(of: "_", with: " ")
        return decodeQuotedPrintable(Data(normalized.utf8))
    }

    static func paddedBase64(_ text: String) -> String {
        switch text.count % 4 {
        case 2: text + "=="
        case 3: text + "="
        default: text
        }
    }

    static func isFoldingWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\t" || scalar == "\r" || scalar == "\n"
    }
}
