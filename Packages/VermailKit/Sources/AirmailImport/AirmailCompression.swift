import Foundation
import zlib

enum AirmailCompression {
    static func text(from data: Data, compressed: Bool) -> String {
        let payload = expanded(data, compressed: compressed)
        return String(decoding: payload, as: UTF8.self)
            .replacingOccurrences(of: "\u{0}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Airmail sets `ezip` and stores either raw gzip or the base64 text of that gzip (`H4sI…`).
    private static func expanded(_ data: Data, compressed: Bool) -> Data {
        if isGzip(data), let inflated = decompress(data) {
            return inflated
        }
        if let inflated = decompressBase64(data) {
            return inflated
        }
        if compressed, let inflated = decompress(data) {
            return inflated
        }
        return data
    }

    private static func decompressBase64(_ data: Data) -> Data? {
        guard isBase64Gzip(data) else { return nil }
        let ascii = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let decoded = Data(base64Encoded: ascii, options: .ignoreUnknownCharacters) else { return nil }
        return decompress(decoded)
    }

    private static func isBase64Gzip(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        let start = data.startIndex
        return data[start] == 0x48
            && data[start + 1] == 0x34
            && data[start + 2] == 0x73
            && data[start + 3] == 0x49
    }

    static func isGzip(_ data: Data) -> Bool {
        data.count > 2 && data[data.startIndex] == 0x1F && data[data.index(after: data.startIndex)] == 0x8B
    }

    static func decompress(_ source: Data) -> Data? {
        guard !source.isEmpty else { return nil }
        return inflate(source, windowBits: 15 + 32) ?? inflate(source, windowBits: 15)
    }

    private static func inflate(_ source: Data, windowBits: Int32) -> Data? {
        let box = InflateBox()
        let status = inflateInit2_(&box.stream, windowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else { return nil }
        defer { inflateEnd(&box.stream) }
        return inflateAll(source, box: box)
    }

    private static func inflateAll(_ source: Data, box: InflateBox) -> Data? {
        var input = [UInt8](source)
        var output = [UInt8]()
        var buffer = [UInt8](repeating: 0, count: 32768)
        var failed = false
        input.withUnsafeMutableBufferPointer { inputBuffer in
            box.stream.next_in = inputBuffer.baseAddress
            box.stream.avail_in = uInt(inputBuffer.count)
            while box.stream.avail_in > 0, !failed {
                let count = writeChunk(&buffer, box: box, failed: &failed)
                if count > 0 {
                    output.append(contentsOf: buffer.prefix(count))
                }
                if box.stream.avail_out != 0 {
                    break
                }
            }
        }
        guard !failed else { return nil }
        return Data(output)
    }

    private static func writeChunk(_ buffer: inout [UInt8], box: InflateBox, failed: inout Bool) -> Int {
        buffer.withUnsafeMutableBufferPointer { outputBuffer in
            box.stream.next_out = outputBuffer.baseAddress
            box.stream.avail_out = uInt(outputBuffer.count)
            let result = zlib.inflate(&box.stream, Z_NO_FLUSH)
            if result != Z_OK, result != Z_STREAM_END {
                failed = true
                return 0
            }
            return outputBuffer.count - Int(box.stream.avail_out)
        }
    }
}

private final class InflateBox {
    var stream = z_stream()
}
