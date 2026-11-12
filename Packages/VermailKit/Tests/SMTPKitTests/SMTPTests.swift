import MailTransport
import SMTPKit
import Testing

struct SMTPTests {
    @Test(arguments: [(ConnectionSecurity.none, 25), (.startTLS, 587), (.ssl, 465)])
    func defaultPort(security: ConnectionSecurity, port: Int) {
        #expect(SMTP.defaultPort(for: security) == port)
    }
}
