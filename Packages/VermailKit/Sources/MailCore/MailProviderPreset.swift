import Foundation

public struct MailProviderPreset: Hashable, Codable, Sendable {
    public var identifier: String
    public var displayName: String
    public var domains: Set<String>
    public var incoming: IncomingServerSettings
    public var outgoing: OutgoingServerSettings

    public init(
        identifier: String,
        displayName: String,
        domains: Set<String>,
        incoming: IncomingServerSettings,
        outgoing: OutgoingServerSettings
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.domains = Set(domains.map { $0.lowercased() })
        self.incoming = incoming
        self.outgoing = outgoing
    }
}

public enum MailProviderPresets {
    public static let all: [MailProviderPreset] = [
        MailProviderPreset(
            identifier: "mailru",
            displayName: "Mail.ru",
            domains: ["mail.ru", "inbox.ru", "list.ru", "bk.ru"],
            incoming: .init(
                protocolKind: .pop3,
                host: "pop.mail.ru",
                port: 995,
                security: .ssl,
                authentication: .userPassword
            ),
            outgoing: .init(
                host: "smtp.mail.ru",
                port: 465,
                security: .ssl,
                authentication: .userPassword,
                requiresAuthentication: true
            )
        ),
        MailProviderPreset(
            identifier: "yandex",
            displayName: "Yandex",
            domains: ["yandex.ru", "yandex.com", "ya.ru", "yandex.by", "yandex.kz", "yandex.uz", "yandex.com.tr"],
            incoming: .init(
                protocolKind: .pop3,
                host: "pop.yandex.ru",
                port: 995,
                security: .ssl,
                authentication: .userPassword
            ),
            outgoing: .init(
                host: "smtp.yandex.ru",
                port: 465,
                security: .ssl,
                authentication: .userPassword,
                requiresAuthentication: true
            )
        ),
        MailProviderPreset(
            identifier: "gmail",
            displayName: "Gmail",
            domains: ["gmail.com", "googlemail.com"],
            incoming: .init(
                protocolKind: .pop3,
                host: "pop.gmail.com",
                port: 995,
                security: .ssl,
                authentication: .xoauth2
            ),
            outgoing: .init(
                host: "smtp.gmail.com",
                port: 465,
                security: .ssl,
                authentication: .xoauth2,
                requiresAuthentication: true
            )
        ),
        MailProviderPreset(
            identifier: "outlook",
            displayName: "Outlook",
            domains: ["outlook.com", "hotmail.com", "live.com", "msn.com"],
            incoming: .init(
                protocolKind: .pop3,
                host: "outlook.office365.com",
                port: 995,
                security: .ssl,
                authentication: .xoauth2
            ),
            outgoing: .init(
                host: "smtp.office365.com",
                port: 587,
                security: .startTLS,
                authentication: .xoauth2,
                requiresAuthentication: true
            )
        ),
        MailProviderPreset(
            identifier: "icloud",
            displayName: "iCloud",
            domains: ["icloud.com", "me.com", "mac.com"],
            incoming: .init(
                protocolKind: .pop3,
                host: "pop.mail.me.com",
                port: 995,
                security: .ssl,
                authentication: .userPassword
            ),
            outgoing: .init(
                host: "smtp.mail.me.com",
                port: 587,
                security: .startTLS,
                authentication: .userPassword,
                requiresAuthentication: true
            )
        ),
        MailProviderPreset(
            identifier: "rambler",
            displayName: "Rambler",
            domains: ["rambler.ru", "lenta.ru", "autorambler.ru", "myrambler.ru", "ro.ru"],
            incoming: .init(
                protocolKind: .pop3,
                host: "pop.rambler.ru",
                port: 995,
                security: .ssl,
                authentication: .userPassword
            ),
            outgoing: .init(
                host: "smtp.rambler.ru",
                port: 465,
                security: .ssl,
                authentication: .userPassword,
                requiresAuthentication: true
            )
        ),
    ]

    public static func preset(forEmailAddress emailAddress: String) -> MailProviderPreset? {
        guard let domain = emailAddress.split(separator: "@").last else {
            return nil
        }
        return preset(forDomain: String(domain))
    }

    public static func preset(forDomain domain: String) -> MailProviderPreset? {
        let normalized = domain.lowercased()
        return all.first(where: { $0.domains.contains(normalized) })
    }
}
