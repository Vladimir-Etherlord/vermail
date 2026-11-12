import Foundation
import MailCore

struct AccountSettingsService: Sendable {
    let accountStore: AccountStore
    let secretStore: any AccountSecretStore
    let identityStore: ComposeIdentityStore

    func draft(for account: MailAccount) async throws -> AccountDraft {
        let details = account.details ?? AccountDetails()
        let incomingPassword = try await secretStore.readSecret(for: account.id, kind: .incomingPassword)
        let outgoingPassword = try await secretStore.readSecret(for: account.id, kind: .outgoingPassword)
        let token = try await secretStore.readSecret(for: account.id, kind: .oauthAccessToken)
        let incomingSecret = account.incomingServer?.authentication == .xoauth2 ? token : incomingPassword
        let outgoingSecret = account.outgoingServer?.authentication == .xoauth2 ? token : outgoingPassword
        let aliases = try identityStore.identities(for: [account])
        return try AccountDraft(
            id: account.id,
            displayName: account.displayName,
            summary: details.summary,
            emailAddress: account.emailAddress,
            symbolName: details.symbolName,
            colorName: details.colorName,
            isIncludedInUnifiedFolders: account.isIncludedInUnifiedFolders,
            isEnabled: account.isEnabled,
            incomingHost: account.incomingServer?.host ?? "",
            incomingPort: account.incomingServer?.port ?? 995,
            incomingSecurity: account.incomingServer?.security ?? .ssl,
            incomingAuthentication: account.incomingServer?.authentication ?? .userPassword,
            incomingUsername: details.incomingUsername,
            incomingSecret: "",
            hasStoredIncomingSecret: !(incomingSecret ?? "").isEmpty,
            outgoingHost: account.outgoingServer?.host ?? "",
            outgoingPort: account.outgoingServer?.port ?? 465,
            outgoingSecurity: account.outgoingServer?.security ?? .ssl,
            outgoingAuthentication: account.outgoingServer?.authentication ?? .userPassword,
            outgoingRequiresAuthentication: account.outgoingServer?.requiresAuthentication ?? true,
            outgoingUsername: details.outgoingUsername,
            outgoingSecret: "",
            hasStoredOutgoingSecret: !(outgoingSecret ?? "").isEmpty,
            allowsInvalidCertificates: details.allowsInvalidCertificates,
            checkIntervalMinutes: details.checkIntervalMinutes,
            leaveMailOnServer: details.leaveMailOnServer,
            deleteAfterDaysEnabled: details.deleteFromServerAfterDays != nil,
            deleteFromServerAfterDays: details.deleteFromServerAfterDays ?? 14,
            deleteFromServerWhenDeletedLocally: details.deleteFromServerWhenDeletedLocally,
            aliases: aliases,
            signature: identityStore.signature(for: account.id)
        )
    }

    func save(_ draft: AccountDraft, existing: [MailAccount]) async throws -> [MailAccount] {
        if let message = draft.validate() {
            throw AccountSettingsError.invalid(message)
        }
        let account = draft.makeAccount()
        var accounts = existing
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        try accountStore.saveAccounts(accounts)
        try await storeSecrets(from: draft, account: account)
        let aliases = normalizedAliases(draft.aliases, account: account)
        try identityStore.replaceIdentities(aliases, for: account.id, signature: draft.signature)
        return accounts
    }

    func delete(id: UUID, existing: [MailAccount]) async throws -> [MailAccount] {
        let accounts = existing.filter { $0.id != id }
        try accountStore.saveAccounts(accounts)
        for kind in AccountSecretKind.allCases {
            try await secretStore.deleteSecret(for: id, kind: kind)
        }
        try identityStore.removeAccount(id)
        return accounts
    }

    private func storeSecrets(from draft: AccountDraft, account: MailAccount) async throws {
        if account.incomingServer?.authentication == .xoauth2 {
            try await store(draft.incomingSecret, for: account.id, kind: .oauthAccessToken)
        } else {
            try await store(draft.incomingSecret, for: account.id, kind: .incomingPassword)
        }
        if account.outgoingServer?.authentication == .xoauth2 {
            try await store(draft.outgoingSecret, for: account.id, kind: .oauthAccessToken)
        } else {
            try await store(draft.outgoingSecret, for: account.id, kind: .outgoingPassword)
        }
    }

    private func store(_ secret: String, for accountID: UUID, kind: AccountSecretKind) async throws {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try await secretStore.saveSecret(trimmed, for: accountID, kind: kind)
    }

    private func normalizedAliases(_ aliases: [MailIdentity], account: MailAccount) -> [MailIdentity] {
        var result = aliases.map { identity in
            var copy = identity
            copy.accountID = account.id
            copy.emailAddress = copy.emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            copy.displayName = copy.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            return copy
        }.filter { $0.emailAddress.contains("@") }
        if !result.contains(where: { $0.emailAddress.caseInsensitiveCompare(account.emailAddress) == .orderedSame }) {
            result.insert(
                MailIdentity(
                    accountID: account.id,
                    displayName: account.displayName,
                    emailAddress: account.emailAddress
                ),
                at: 0
            )
        }
        return result
    }
}

enum AccountSettingsError: Error, LocalizedError, Equatable {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case let .invalid(message): message
        }
    }
}
