import Foundation
import MailCore

extension MainWindowViewModel {
    func saveAccount(_ draft: AccountDraft) async throws {
        if accounts.isEmpty {
            accounts = try accountStore.loadAccounts()
        }
        accounts = try await settingsService().save(draft, existing: accounts)
        await reloadMessages()
    }

    func deleteAccount(id: UUID) async throws {
        accounts = try await settingsService().delete(id: id, existing: accounts)
        if selectedMessage?.accountID == id {
            selectedMessageIDs = []
            selectedMessageID = nil
            selectedParsedMessage = nil
        }
        await reloadMessages()
    }

    func accountDraft(for account: MailAccount) async throws -> AccountDraft {
        try await settingsService().draft(for: account)
    }

    func storedSecret(for accountID: UUID, kind: AccountSecretKind) async -> String? {
        try? await secretStore.readSecret(for: accountID, kind: kind)
    }

    private func settingsService() -> AccountSettingsService {
        AccountSettingsService(
            accountStore: accountStore,
            secretStore: secretStore,
            identityStore: identityStore
        )
    }
}
