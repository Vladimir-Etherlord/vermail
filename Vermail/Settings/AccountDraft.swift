import Foundation
import MailCore

enum AccountCredentialChoice: Equatable {
    case appPassword
    case accessToken
}

struct AccountDraft: Identifiable, Equatable {
    var id: UUID
    var displayName: String
    var summary: String
    var emailAddress: String
    var symbolName: String
    var colorName: String
    var isIncludedInUnifiedFolders: Bool
    var isEnabled: Bool
    var incomingProtocol: IncomingProtocol
    var incomingHost: String
    var incomingPort: Int
    var incomingSecurity: ServerSecurity
    var incomingAuthentication: ServerAuthenticationMethod
    var incomingUsername: String
    var incomingSecret: String
    var hasStoredIncomingSecret: Bool
    var outgoingHost: String
    var outgoingPort: Int
    var outgoingSecurity: ServerSecurity
    var outgoingAuthentication: ServerAuthenticationMethod
    var outgoingRequiresAuthentication: Bool
    var outgoingUsername: String
    var outgoingSecret: String
    var hasStoredOutgoingSecret: Bool
    var allowsInvalidCertificates: Bool
    var checkIntervalMinutes: Int
    var leaveMailOnServer: Bool
    var deleteAfterDaysEnabled: Bool
    var deleteFromServerAfterDays: Int
    var deleteFromServerWhenDeletedLocally: Bool
    var aliases: [MailIdentity]
    var signature: String

    static func makeNew() -> AccountDraft {
        AccountDraft(
            id: UUID(),
            displayName: "",
            summary: "",
            emailAddress: "",
            symbolName: "envelope.fill",
            colorName: "blue",
            isIncludedInUnifiedFolders: true,
            isEnabled: true,
            incomingProtocol: .pop3,
            incomingHost: "",
            incomingPort: 995,
            incomingSecurity: .ssl,
            incomingAuthentication: .userPassword,
            incomingUsername: "",
            incomingSecret: "",
            hasStoredIncomingSecret: false,
            outgoingHost: "",
            outgoingPort: 465,
            outgoingSecurity: .ssl,
            outgoingAuthentication: .userPassword,
            outgoingRequiresAuthentication: true,
            outgoingUsername: "",
            outgoingSecret: "",
            hasStoredOutgoingSecret: false,
            allowsInvalidCertificates: false,
            checkIntervalMinutes: 5,
            leaveMailOnServer: true,
            deleteAfterDaysEnabled: false,
            deleteFromServerAfterDays: 14,
            deleteFromServerWhenDeletedLocally: false,
            aliases: [],
            signature: ""
        )
    }

    func validate() -> String? {
        let email = emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !email.contains("@") || email.hasSuffix("@") {
            return String(localized: "Enter a valid email address.")
        }
        if incomingHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            outgoingHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return String(localized: "Enter the incoming and outgoing server addresses.")
        }
        if !(1 ... 65535).contains(incomingPort) || !(1 ... 65535).contains(outgoingPort) {
            return String(localized: "Port must be between 1 and 65535.")
        }
        return nil
    }

    func makeAccount() -> MailAccount {
        let trimmedEmail = emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return MailAccount(
            id: id,
            displayName: name.isEmpty ? trimmedEmail : name,
            emailAddress: trimmedEmail,
            incomingProtocol: incomingProtocol,
            isIncludedInUnifiedFolders: isIncludedInUnifiedFolders,
            incomingServer: IncomingServerSettings(
                protocolKind: incomingProtocol,
                host: incomingHost.trimmingCharacters(in: .whitespacesAndNewlines),
                port: incomingPort,
                security: incomingSecurity,
                authentication: incomingAuthentication
            ),
            outgoingServer: OutgoingServerSettings(
                host: outgoingHost.trimmingCharacters(in: .whitespacesAndNewlines),
                port: outgoingPort,
                security: outgoingSecurity,
                authentication: outgoingAuthentication,
                requiresAuthentication: outgoingRequiresAuthentication
            ),
            isEnabled: isEnabled,
            details: AccountDetails(
                summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
                symbolName: symbolName,
                colorName: colorName,
                incomingUsername: incomingUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                outgoingUsername: outgoingUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                allowsInvalidCertificates: allowsInvalidCertificates,
                checkIntervalMinutes: min(max(checkIntervalMinutes, 1), 1440),
                leaveMailOnServer: leaveMailOnServer,
                deleteFromServerAfterDays: deleteAfterDaysEnabled ? deleteFromServerAfterDays : nil,
                deleteFromServerWhenDeletedLocally: deleteFromServerWhenDeletedLocally
            )
        )
    }

    func applyingDiscovery(_ result: MailAutoconfigResult) -> AccountDraft {
        var copy = self
        if let incoming = result.incomingCandidates.first {
            copy.incomingProtocol = incoming.protocolKind
            copy.incomingHost = incoming.host
            copy.incomingPort = incoming.port
            copy.incomingSecurity = incoming.security
            copy.incomingAuthentication = incoming.authentication
        }
        if let outgoing = result.outgoing {
            copy.outgoingHost = outgoing.host
            copy.outgoingPort = outgoing.port
            copy.outgoingSecurity = outgoing.security
            copy.outgoingAuthentication = outgoing.authentication
            copy.outgoingRequiresAuthentication = outgoing.requiresAuthentication
        }
        if copy.displayName.isEmpty,
           let presetName = MailProviderPresets.preset(forDomain: result.domain)?.displayName
        {
            copy.displayName = presetName
        }
        return copy
    }

    func applying(incomingProtocol newProtocol: IncomingProtocol) -> AccountDraft {
        var copy = self
        copy.incomingProtocol = newProtocol
        if newProtocol == .imap, copy.incomingAuthentication == .apop {
            copy.incomingAuthentication = .userPassword
        }
        if let preset = MailProviderPresets.preset(forEmailAddress: emailAddress) {
            let server = newProtocol == .imap ? preset.imap : preset.incoming
            copy.incomingHost = server.host
            copy.incomingPort = server.port
            copy.incomingSecurity = server.security
            copy.incomingAuthentication = server.authentication
            return copy
        }
        return copy.retargetingGenericServer(to: newProtocol)
    }

    func applyingCredentialChoice(_ choice: AccountCredentialChoice) -> AccountDraft {
        var copy = self
        switch choice {
        case .appPassword:
            copy.incomingAuthentication = .userPassword
            copy.outgoingAuthentication = .userPassword
        case .accessToken:
            copy.incomingAuthentication = .xoauth2
            copy.outgoingAuthentication = .xoauth2
        }
        return copy
    }

    private func retargetingGenericServer(to protocolKind: IncomingProtocol) -> AccountDraft {
        var copy = self
        switch protocolKind {
        case .imap:
            copy.incomingPort = Self.switchedPort(copy.incomingPort, to: .imap, security: copy.incomingSecurity)
            if copy.incomingHost.lowercased().hasPrefix("pop.") {
                copy.incomingHost = "imap." + copy.incomingHost.dropFirst(4)
            }
        case .pop3:
            copy.incomingPort = Self.switchedPort(copy.incomingPort, to: .pop3, security: copy.incomingSecurity)
            if copy.incomingHost.lowercased().hasPrefix("imap.") {
                copy.incomingHost = "pop." + copy.incomingHost.dropFirst(5)
            }
        }
        return copy
    }

    private static func switchedPort(_ port: Int, to protocolKind: IncomingProtocol, security: ServerSecurity) -> Int {
        switch protocolKind {
        case .imap:
            guard port == 995 || port == 110 else { return port }
            return security == .ssl ? 993 : 143
        case .pop3:
            guard port == 993 || port == 143 else { return port }
            return security == .ssl ? 995 : 110
        }
    }
}
