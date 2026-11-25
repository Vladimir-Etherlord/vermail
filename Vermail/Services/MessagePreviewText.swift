import Foundation

extension MessageMetadataExtractor {
    static func decodeHTMLEntities(_ text: String) -> String {
        var current = text
        for _ in 0 ..< 2 {
            current = replacingHTMLEntities(in: current)
        }
        return current
    }

    static func removingInvisibleCharacters(_ text: String) -> String {
        String(text.unicodeScalars.filter { !isPreviewSpacer($0) })
    }

    /// Drops a run of zero-width or blank padding. The readable preheader is the text before it.
    static func cuttingPreviewPadding(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var runStart: Int?
        var spacers = 0
        for (index, scalar) in scalars.enumerated() {
            if isPreviewSpacer(scalar) || isPreviewWhitespace(scalar) {
                if runStart == nil {
                    runStart = index
                }
                if isPreviewSpacer(scalar) {
                    spacers += 1
                }
                if spacers >= 4, let runStart {
                    return String(String.UnicodeScalarView(scalars[..<runStart]))
                }
            } else {
                runStart = nil
                spacers = 0
            }
        }
        return text
    }

    private static func replacingHTMLEntities(in text: String) -> String {
        let pattern = #"&(?:#x([0-9A-Fa-f]{1,6})|#([0-9]{1,7})|([A-Za-z][A-Za-z0-9]{0,31}));"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let source = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return text }
        var result = ""
        var cursor = 0
        for match in matches {
            let full = match.range(at: 0)
            if full.location > cursor {
                result += source.substring(with: NSRange(location: cursor, length: full.location - cursor))
            }
            result += htmlEntity(source, match)
            cursor = full.location + full.length
        }
        if cursor < source.length {
            result += source.substring(from: cursor)
        }
        return result
    }

    private static func htmlEntity(_ source: NSString, _ match: NSTextCheckingResult) -> String {
        if match.range(at: 1).location != NSNotFound {
            return character(hex: source.substring(with: match.range(at: 1))) ?? source.substring(with: match.range)
        }
        if match.range(at: 2).location != NSNotFound {
            return character(decimal: source.substring(with: match.range(at: 2))) ?? source.substring(with: match.range)
        }
        let name = source.substring(with: match.range(at: 3)).lowercased()
        return namedHTMLEntities[name] ?? source.substring(with: match.range)
    }

    private static func character(hex: String) -> String? {
        guard let value = UInt32(hex, radix: 16) else { return nil }
        return character(codePoint: value)
    }

    private static func character(decimal: String) -> String? {
        guard let value = UInt32(decimal) else { return nil }
        return character(codePoint: value)
    }

    private static func character(codePoint: UInt32) -> String? {
        guard let scalar = Unicode.Scalar(codePoint) else { return nil }
        return String(scalar)
    }

    private static func isPreviewWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    private static func isPreviewSpacer(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00AD, 0x034F, 0x180E, 0x200B, 0x200C, 0x200D, 0x200E, 0x200F, 0x2060, 0x2800, 0xFEFF:
            true
        case 0x2061 ... 0x2064:
            true
        default:
            false
        }
    }

    private static let namedHTMLEntities: [String: String] = [
        "nbsp": " ",
        "amp": "&",
        "lt": "<",
        "gt": ">",
        "quot": "\"",
        "apos": "'",
        "zwnj": "\u{200C}",
        "zwj": "\u{200D}",
        "lrm": "\u{200E}",
        "rlm": "\u{200F}",
        "shy": "\u{00AD}",
        "ndash": "\u{2013}",
        "mdash": "\u{2014}",
        "hellip": "\u{2026}",
        "laquo": "\u{00AB}",
        "raquo": "\u{00BB}",
    ]
}
