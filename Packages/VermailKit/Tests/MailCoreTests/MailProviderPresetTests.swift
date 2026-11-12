import MailCore
import Testing

struct MailProviderPresetTests {
    @Test func findsMailRuAliasDomain() {
        let preset = MailProviderPresets.preset(forDomain: "INBOX.RU")
        #expect(preset?.identifier == "mailru")
        #expect(preset?.incoming.host == "pop.mail.ru")
        #expect(preset?.outgoing.host == "smtp.mail.ru")
    }

    @Test func findsOutlookByEmailAddress() {
        let preset = MailProviderPresets.preset(forEmailAddress: "user@outlook.com")
        #expect(preset?.identifier == "outlook")
        #expect(preset?.incoming.security == .ssl)
        #expect(preset?.outgoing.security == .startTLS)
    }

    @Test func unknownDomainHasNoPreset() {
        #expect(MailProviderPresets.preset(forDomain: "example.dev") == nil)
    }
}
