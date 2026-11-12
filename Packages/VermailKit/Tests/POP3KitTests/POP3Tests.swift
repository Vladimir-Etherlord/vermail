import MailTransport
import POP3Kit
import Testing

struct POP3Tests {
    @Test(arguments: [(ConnectionSecurity.none, 110), (.startTLS, 110), (.ssl, 995)])
    func defaultPort(security: ConnectionSecurity, port: Int) {
        #expect(POP3.defaultPort(for: security) == port)
    }
}
