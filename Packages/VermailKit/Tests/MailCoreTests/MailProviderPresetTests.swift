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

    @Test func findsYandexRegionalDomains() {
        #expect(MailProviderPresets.preset(forDomain: "yandex.kz")?.identifier == "yandex")
        #expect(MailProviderPresets.preset(forEmailAddress: "user@yandex.com.tr")?.identifier == "yandex")
    }

    @Test func providerMatrixMatchesDocumentedServers() throws {
        for row in ProviderServerExpectation.matrix {
            let preset = try #require(MailProviderPresets.preset(forEmailAddress: row.email))
            #expect(preset.identifier == row.identifier)
            #expect(preset.incoming.host == row.popHost)
            #expect(preset.incoming.port == row.popPort)
            #expect(preset.incoming.security == row.popSecurity)
            #expect(preset.incoming.authentication == row.popAuth)
            #expect(preset.outgoing.host == row.smtpHost)
            #expect(preset.outgoing.port == row.smtpPort)
            #expect(preset.outgoing.security == row.smtpSecurity)
            #expect(preset.outgoing.authentication == row.smtpAuth)
        }
    }
}

private struct ProviderServerExpectation {
    var email: String
    var identifier: String
    var popHost: String
    var popPort: Int
    var popSecurity: ServerSecurity
    var popAuth: ServerAuthenticationMethod
    var smtpHost: String
    var smtpPort: Int
    var smtpSecurity: ServerSecurity
    var smtpAuth: ServerAuthenticationMethod

    static let matrix: [ProviderServerExpectation] = [
        ProviderServerExpectation(
            email: "user@mail.ru",
            identifier: "mailru",
            popHost: "pop.mail.ru",
            popPort: 995,
            popSecurity: .ssl,
            popAuth: .userPassword,
            smtpHost: "smtp.mail.ru",
            smtpPort: 465,
            smtpSecurity: .ssl,
            smtpAuth: .userPassword
        ),
        ProviderServerExpectation(
            email: "user@yandex.ru",
            identifier: "yandex",
            popHost: "pop.yandex.ru",
            popPort: 995,
            popSecurity: .ssl,
            popAuth: .userPassword,
            smtpHost: "smtp.yandex.ru",
            smtpPort: 465,
            smtpSecurity: .ssl,
            smtpAuth: .userPassword
        ),
        ProviderServerExpectation(
            email: "user@gmail.com",
            identifier: "gmail",
            popHost: "pop.gmail.com",
            popPort: 995,
            popSecurity: .ssl,
            popAuth: .xoauth2,
            smtpHost: "smtp.gmail.com",
            smtpPort: 465,
            smtpSecurity: .ssl,
            smtpAuth: .xoauth2
        ),
        ProviderServerExpectation(
            email: "user@outlook.com",
            identifier: "outlook",
            popHost: "outlook.office365.com",
            popPort: 995,
            popSecurity: .ssl,
            popAuth: .xoauth2,
            smtpHost: "smtp.office365.com",
            smtpPort: 587,
            smtpSecurity: .startTLS,
            smtpAuth: .xoauth2
        ),
    ]
}
