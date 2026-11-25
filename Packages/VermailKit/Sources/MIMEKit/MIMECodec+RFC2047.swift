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

    /// Adjacent encoded-words of the same charset are one byte string. Senders split UTF-8
    /// characters across the 75-character limit, so each word alone is not valid text.
    static func decodeRFC2047Runs(_ value: String) -> String {
        guard let matches = encodedWordMatches(in: value), !matches.isEmpty else { return value }
        let source = value as NSString
        var result = ""
        var cursor = 0
        var index = 0
        while index < matches.count {
            let start = matches[index]
            appendFoldingGap(from: source, start: cursor, end: start.range.location, into: &result)
            let end = endOfEncodedWordRun(matches, from: index, in: source)
            result += decodedRun(Array(matches[index ... end]), in: source)
            let last = matches[end].range
            cursor = last.location + last.length
            index = end + 1
        }
        if cursor < source.length {
            result += source.substring(from: cursor)
        }
        return result
    }

    private static func encodedWordMatches(in value: String) -> [NSTextCheckingResult]? {
        let pattern = #"=\?([^?]+)\?([bBqQ])\?([^?]+)\?="#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(location: 0, length: (value as NSString).length)
        return regex.matches(in: value, range: range)
    }

    private static func endOfEncodedWordRun(
        _ matches: [NSTextCheckingResult],
        from start: Int,
        in value: NSString
    ) -> Int {
        var end = start
        while end + 1 < matches.count, sameEncodedWordRun(matches[end], matches[end + 1], in: value) {
            end += 1
        }
        return end
    }

    private static func sameEncodedWordRun(
        _ current: NSTextCheckingResult,
        _ next: NSTextCheckingResult,
        in value: NSString
    ) -> Bool {
        let gapStart = current.range.location + current.range.length
        let gapLength = next.range.location - gapStart
        guard gapLength >= 0 else { return false }
        let gap = value.substring(with: NSRange(location: gapStart, length: gapLength))
        guard gap.unicodeScalars.allSatisfy(isFoldingWhitespace) else { return false }
        let left = encodedWordPiece(current, in: value)
        let right = encodedWordPiece(next, in: value)
        let sameCharset = left.charset.caseInsensitiveCompare(right.charset) == .orderedSame
        let sameEncoding = left.encoding.lowercased() == right.encoding.lowercased()
        return sameCharset && sameEncoding
    }

    private static func decodedRun(_ matches: [NSTextCheckingResult], in value: NSString) -> String {
        let words = matches.map { encodedWordPiece($0, in: value) }
        if let decoded = decodeEncodedWordRun(words) {
            return decoded
        }
        return matches.map { match in
            decodedEncodedWord(value, match) ?? value.substring(with: match.range)
        }.joined()
    }

    private struct EncodedWordPiece {
        var charset: String
        var encoding: String
        var payload: String
    }

    private static func encodedWordPiece(_ match: NSTextCheckingResult, in value: NSString) -> EncodedWordPiece {
        EncodedWordPiece(
            charset: value.substring(with: match.range(at: 1)),
            encoding: value.substring(with: match.range(at: 2)),
            payload: value.substring(with: match.range(at: 3))
        )
    }

    private static func decodeEncodedWordRun(_ words: [EncodedWordPiece]) -> String? {
        guard let first = words.first else { return nil }
        let data = encodedWordRunBytes(words, encoding: first.encoding.lowercased())
        guard let data else { return nil }
        return decodeBytes(data, charset: first.charset)
    }

    private static func encodedWordRunBytes(_ words: [EncodedWordPiece], encoding: String) -> Data? {
        if encoding == "b" {
            let joined = words.map(base64Payload).joined()
            return Data(base64Encoded: paddedBase64(joined), options: .ignoreUnknownCharacters)
        }
        guard encoding == "q" else { return nil }
        var bytes = Data()
        for word in words {
            guard let part = encodedWordBytes(encoding: "q", payload: word.payload) else { return nil }
            bytes.append(part)
        }
        return bytes
    }

    private static func base64Payload(_ word: EncodedWordPiece) -> String {
        String(word.payload.unicodeScalars.filter { !isFoldingWhitespace($0) && $0 != "=" })
    }
}
