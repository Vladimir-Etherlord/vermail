import Foundation
import Testing
@testable import MailTransport

struct LineBufferTests {
    @Test func splitsCRLFAndBareLF() throws {
        var buffer = LineBuffer()
        buffer.append(Data("+OK ready\r\nline two\nlast\r\n".utf8))
        #expect(try buffer.nextLine() == Data("+OK ready".utf8))
        #expect(try buffer.nextLine() == Data("line two".utf8))
        #expect(try buffer.nextLine() == Data("last".utf8))
        #expect(try buffer.nextLine() == nil)
        #expect(buffer.isEmpty)
    }

    @Test func waitsForLineAcrossChunks() throws {
        var buffer = LineBuffer()
        buffer.append(Data("250-smtp.mail".utf8))
        #expect(try buffer.nextLine() == nil)
        buffer.append(Data(".ru\r".utf8))
        #expect(try buffer.nextLine() == nil)
        buffer.append(Data("\n".utf8))
        #expect(try buffer.nextLine() == Data("250-smtp.mail.ru".utf8))
    }

    @Test func keepsEmptyLinesAndRawBytes() throws {
        var buffer = LineBuffer()
        let cp1251Privet = Data([0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2])
        buffer.append(Data("\r\n".utf8) + cp1251Privet + Data("\r\n".utf8))
        #expect(try buffer.nextLine() == Data())
        #expect(try buffer.nextLine() == cp1251Privet)
    }

    @Test func rejectsEndlessLine() {
        var buffer = LineBuffer(maxLineLength: 8)
        buffer.append(Data("0123456789".utf8))
        #expect(throws: TransportError.lineTooLong) { try buffer.nextLine() }
    }

    @Test func handlesLargeMessageEfficiently() throws {
        var buffer = LineBuffer()
        let line = String(repeating: "x", count: 76) + "\r\n"
        let count = 200_000
        for _ in 0 ..< count / 1000 {
            buffer.append(Data(String(repeating: line, count: 1000).utf8))
        }
        var lines = 0
        while try buffer.nextLine() != nil {
            lines += 1
        }
        #expect(lines == count)
    }
}
