import Foundation

public struct MailProviderPreset: Hashable, Codable, Sendable {
    public var identifier: String
    public var displayName: String
    public var domains: Set<String>
    public var incoming: IncomingServerSettings
    public var imap: IncomingServerSettings
    public var outgoing: OutgoingServerSettings

    public init(
        identifier: String,
        displayName: String,
        domains: Set<String>,
        incoming: IncomingServerSettings,
        imap: IncomingServerSettings,
        outgoing: OutgoingServerSettings
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.domains = Set(domains.map { $0.lowercased() })
        self.incoming = incoming
        self.imap = imap
        self.outgoing = outgoing
    }
}

private func mailServer(
    kind: IncomingProtocol,
    host: String,
    authentication: ServerAuthenticationMethod
) -> IncomingServerSettings {
    IncomingServerSettings(
        protocolKind: kind,
        host: host,
        port: kind == .imap ? 993 : 995,
        security: .ssl,
        authentication: authentication
    )
}

public enum MailProviderPresets {
    public static let all: [MailProviderPreset] = [
        MailProviderPreset(
            identifier: "mailru",
            displayName: "Mail.ru",
            domains: ["mail.ru", "inbox.ru", "list.ru", "bk.ru"],
            incoming: mailServer(kind: .pop3, host: "pop.mail.ru", authentication: .userPassword),
            imap: mailServer(kind: .imap, host: "imap.mail.ru", authentication: .userPassword),
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
            incoming: mailServer(kind: .pop3, host: "pop.yandex.ru", authentication: .userPassword),
            imap: mailServer(kind: .imap, host: "imap.yandex.ru", authentication: .userPassword),
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
            incoming: mailServer(kind: .pop3, host: "pop.gmail.com", authentication: .xoauth2),
            imap: mailServer(kind: .imap, host: "imap.gmail.com", authentication: .xoauth2),
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
            incoming: mailServer(kind: .pop3, host: "outlook.office365.com", authentication: .xoauth2),
            imap: mailServer(kind: .imap, host: "outlook.office365.com", authentication: .xoauth2),
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
            incoming: mailServer(kind: .pop3, host: "pop.mail.me.com", authentication: .userPassword),
            imap: mailServer(kind: .imap, host: "imap.mail.me.com", authentication: .userPassword),
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
            incoming: mailServer(kind: .pop3, host: "pop.rambler.ru", authentication: .userPassword),
            imap: mailServer(kind: .imap, host: "imap.rambler.ru", authentication: .userPassword),
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
