import MailTransport
import Testing

struct TransportConfigurationTests {
    @Test func rejectsInvalidCertificatesByDefault() {
        let config = TransportConfiguration(host: "pop.mail.ru", port: 995, security: .ssl)
        #expect(config.allowsInvalidCertificates == false)
    }
}
