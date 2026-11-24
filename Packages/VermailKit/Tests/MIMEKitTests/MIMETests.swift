import Foundation
import MIMEKit
import Testing

struct MIMETests {
    @Test func usesCRLFLineBreaks() {
        #expect(MIME.lineBreak == "\r\n")
    }

    @Test func parseRFC2047AndQuotedPrintableCP1251() throws {
        let raw = Data((
            "Subject: =?UTF-8?B?0J/RgNC40LLQtdGC?=\r\n" +
                "Content-Type: text/plain; charset=windows-1251\r\n" +
                "Content-Transfer-Encoding: quoted-printable\r\n" +
                "\r\n" +
                "=CF=F0=E8=E2=E5=F2"
        ).utf8)

        let message = try MIME.parse(raw)
        #expect(message.subject == "Привет")
        #expect(message.plainBody == "Привет")
    }

    @Test func parseMultipartAttachmentRFC2231AndBase64() throws {
        let raw = Data("""
        Content-Type: multipart/mixed; boundary="b"

        --b
        Content-Type: text/plain; charset=utf-8

        hello
        --b
        Content-Type: application/octet-stream; name*=utf-8''report%20%D1%84%D0%B0%D0%B9%D0%BB.bin
        Content-Disposition: attachment; filename*=utf-8''report%20%D1%84%D0%B0%D0%B9%D0%BB.bin
        Content-Transfer-Encoding: base64

        AQID
        --b--
        """.replacingOccurrences(of: "\n", with: "\r\n").utf8)

        let message = try MIME.parse(raw)
        #expect(message.plainBody == "hello")
        #expect(message.attachments.count == 1)
        #expect(message.attachments[0].filename == "report файл.bin")
        #expect(message.attachments[0].data == Data([1, 2, 3]))
    }

    @Test func parseRFC2231ContinuationFilename() throws {
        let raw = Data("""
        Content-Type: multipart/mixed; boundary=x

        --x
        Content-Type: application/pdf
        Content-Disposition: attachment; filename*0*=utf-8''report%20; filename*1*=%D1%84%D0%B0%D0%B9%D0%BB.pdf
        Content-Transfer-Encoding: base64

        AA==
        --x--
        """.replacingOccurrences(of: "\n", with: "\r\n").utf8)

        let message = try MIME.parse(raw)
        #expect(message.attachments.first?.filename == "report файл.pdf")
    }

    @Test func buildAndParseRoundtripWithAttachment() throws {
        let outgoing = MIMEOutgoingMessage(
            from: "alice@example.com",
            to: ["bob@example.com"],
            subject: "Тестовое письмо",
            plainBody: "Привет, мир",
            htmlBody: "<b>Привет, мир</b>",
            attachments: [
                .init(filename: "файл.txt", mimeType: "text/plain", data: Data("payload".utf8)),
            ]
        )

        let built = MIME.build(outgoing)
        let raw = String(decoding: built, as: UTF8.self)
        #expect(raw.contains("Subject: =?UTF-8?B?"))
        #expect(raw.contains("filename*=utf-8''"))

        let parsed = try MIME.parse(built)
        #expect(parsed.subject == "Тестовое письмо")
        #expect(parsed.plainBody?.contains("Привет") == true)
        #expect(parsed.attachments.count == 1)
        #expect(parsed.attachments[0].filename == "файл.txt")
        #expect(parsed.attachments[0].data == Data("payload".utf8))
    }

    @Test func bccHeaderIsOmittedUnlessRequested() {
        let hidden = MIMEOutgoingMessage(
            from: "alice@example.com",
            to: ["bob@example.com"],
            blindCarbonCopy: ["secret@example.com"],
            subject: "Hello",
            plainBody: "Body"
        )
        let visible = MIMEOutgoingMessage(
            from: "alice@example.com",
            to: ["bob@example.com"],
            blindCarbonCopy: ["secret@example.com"],
            includesBlindCarbonCopyHeader: true,
            subject: "Hello",
            plainBody: "Body"
        )

        let hiddenRaw = String(decoding: MIME.build(hidden), as: UTF8.self)
        let visibleRaw = String(decoding: MIME.build(visible), as: UTF8.self)
        #expect(!hiddenRaw.contains("Bcc:"))
        #expect(visibleRaw.contains("Bcc: secret@example.com"))
    }

    @Test func foldedRFC2047WordsDecodeAcrossTheLineBreak() throws {
        let lines = [
            "Subject: =?UTF-8?B?0J/RgNC4",
            " 0LLQtdGC?=",
            "From: =?UTF-8?Q?=D0=92=D0=BB=D0=B0=D0=B4?=",
            " =?UTF-8?Q?=D0=B8=D0=BC=D0=B8=D1=80?= <v@example.com>",
            "",
            "Body",
        ]
        let raw = Data(lines.joined(separator: "\r\n").utf8)

        let message = try MIME.parse(raw)
        #expect(message.subject == "Привет")
        let from = message.headers.first { $0.name == "From" }?.value
        #expect(from == "Владимир <v@example.com>")
        #expect(MIME.decodedHeader("=?utf-8?B?0J/RgNC4 0LLQtdGC?=") == "Привет")
        #expect(MIME.decodedHeader("Hello") == "Hello")
    }

    @Test func decodesBrokenEncodedWordSeparator() {
        let broken = "=?UTF-8?B?0J/RgNC40LLQtdGC?==?UTF-8?B?INC80LjRgA==?="
        #expect(MIME.decodedHeader(broken) == "Привет мир")
    }
}
