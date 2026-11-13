import Foundation

/// Splits incoming bytes into lines. Accepts CRLF and bare LF; the line terminator is not returned.
/// Bytes are kept raw because message bodies may use any charset.
struct LineBuffer {
    static let defaultMaxLineLength = 1 << 20

    let maxLineLength: Int
    private var bytes: [UInt8] = []
    private var start = 0

    init(maxLineLength: Int = defaultMaxLineLength) {
        self.maxLineLength = maxLineLength
    }

    var isEmpty: Bool {
        start == bytes.count
    }

    mutating func append(_ data: Data) {
        if start > 64 * 1024, start * 2 > bytes.count {
            bytes.removeSubrange(0 ..< start)
            start = 0
        }
        bytes.append(contentsOf: data)
    }

    mutating func nextLine() throws(TransportError) -> Data? {
        guard let newline = bytes[start...].firstIndex(of: 0x0A) else {
            if bytes.count - start > maxLineLength {
                throw .lineTooLong
            }
            return nil
        }
        var end = newline
        if end > start, bytes[end - 1] == 0x0D {
            end -= 1
        }
        let line = Data(bytes[start ..< end])
        start = newline + 1
        return line
    }

    /// Returns up to `maxCount` buffered bytes without waiting for a line ending.
    mutating func nextBytes(maxCount: Int) -> Data? {
        let available = bytes.count - start
        guard available > 0, maxCount > 0 else { return nil }
        let count = min(maxCount, available)
        let data = Data(bytes[start ..< (start + count)])
        start += count
        return data
    }
}
