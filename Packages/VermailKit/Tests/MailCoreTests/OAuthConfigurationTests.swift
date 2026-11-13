import MailCore
import Testing

struct OAuthConfigurationTests {
    @Test func resolveProviderByEmail() {
        #expect(OAuthConfigurationCatalog.provider(forEmailAddress: "u@gmail.com") == .gmail)
        #expect(OAuthConfigurationCatalog.provider(forEmailAddress: "u@outlook.com") == .outlook)
        #expect(OAuthConfigurationCatalog.provider(forEmailAddress: "u@example.com") == nil)
    }

    @Test func outlookCatalogIncludesIMAP() {
        let config = OAuthConfigurationCatalog.configuration(for: .outlook)
        #expect(config.scopes.contains("https://outlook.office.com/IMAP.AccessAsUser.All"))
        #expect(config.scopes.contains("https://outlook.office.com/POP.AccessAsUser.All"))
    }

    @Test func gmailCatalogHasMailScope() {
        let config = OAuthConfigurationCatalog.configuration(for: .gmail)
        #expect(config.scopes.contains("https://mail.google.com/"))
        #expect(config.recommendedIncomingAuth == .xoauth2)
    }

    @Test func xoauth2PayloadFormat() {
        let payload = OAuthConfigurationCatalog.xoauth2Payload(emailAddress: "u@example.com", accessToken: "abc")
        #expect(payload == "dXNlcj11QGV4YW1wbGUuY29tAWF1dGg9QmVhcmVyIGFiYwEB")
    }
}
