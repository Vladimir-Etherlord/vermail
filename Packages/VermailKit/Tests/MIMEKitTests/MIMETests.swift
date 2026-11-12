import MIMEKit
import Testing

struct MIMETests {
    @Test func usesCRLFLineBreaks() {
        #expect(MIME.lineBreak == "\r\n")
    }
}
