import Foundation

/// IMAP mailbox names use a modified UTF-7 (RFC 3501). ASCII stays as-is, `&` is `&-`,
/// and every other character is UTF-16BE base64 with `/` written as `,` and padding removed.
enum IMAPUTF7 {
    static func encode(_ value: String) -> String {
        var encoded = ""
        var pending: [UInt16] = []

        for scalar in value.unicodeScalars {
            if scalar.value >= 0x20, scalar.value <= 0x7E, scalar != "&" {
                flush(&pending, into: &encoded)
                encoded.unicodeScalars.append(scalar)
            } else if scalar == "&" {
                flush(&pending, into: &encoded)
                encoded.append("&-")
            } else {
                pending.append(contentsOf: String(scalar).utf16)
            }
        }
        flush(&pending, into: &encoded)
        return encoded
    }

    static func decode(_ value: String) -> String {
        var decoded = ""
        var index = value.startIndex
        while index < value.endIndex {
            if value[index] != "&" {
                decoded.append(value[index])
                index = value.index(after: index)
                continue
            }
            let next = value.index(after: index)
            if next == value.endIndex {
                decoded.append("&")
                break
            }
            if value[next] == "-" {
                decoded.append("&")
                index = value.index(after: next)
                continue
            }
            guard let end = value[next...].firstIndex(of: "-") else {
                decoded.append(contentsOf: value[index...])
                break
            }
            let payload = value[next ..< end].replacingOccurrences(of: ",", with: "/")
            decoded.append(decodeShifted(payload))
            index = value.index(after: end)
        }
        return decoded
    }

    private static func flush(_ pending: inout [UInt16], into encoded: inout String) {
        guard !pending.isEmpty else { return }
        var bytes = Data()
        bytes.reserveCapacity(pending.count * 2)
        for unit in pending {
            bytes.append(UInt8(unit >> 8))
            bytes.append(UInt8(unit & 0xFF))
        }
        var base64 = bytes.base64EncodedString()
        base64.removeAll { $0 == "=" }
        base64 = base64.replacingOccurrences(of: "/", with: ",")
        encoded.append("&")
        encoded.append(base64)
        encoded.append("-")
        pending.removeAll(keepingCapacity: true)
    }

    private static func decodeShifted(_ payload: String) -> String {
        var base64 = String(payload)
        let remainder = base64.count % 4
        if remainder != 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: base64) else {
            return "&" + payload.replacingOccurrences(of: "/", with: ",") + "-"
        }
        var units: [UInt16] = []
        units.reserveCapacity(data.count / 2)
        var offset = 0
        while offset + 1 < data.count {
            let high = UInt16(data[offset]) << 8
            let low = UInt16(data[offset + 1])
            units.append(high | low)
            offset += 2
        }
        return String(utf16CodeUnits: units, count: units.count)
    }
}
