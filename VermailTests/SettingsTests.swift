import Foundation
import MailCore
import Testing
@testable import Vermail

struct SettingsTests {
    @Test func saveKeepsBlankSecretAndStoresAliases() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SettingsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let secrets = InMemorySecretStore()
        let service = AccountSettingsService(
            accountStore: AccountStore(fileURL: root.appending(path: "accounts.json")),
            secretStore: secrets,
            identityStore: ComposeIdentityStore(fileURL: root.appending(path: "compose.json"))
        )
        var draft = AccountDraft.makeNew()
        draft.displayName = "Work"
        draft.emailAddress = "work@example.com"
        draft.incomingHost = "pop.example.com"
        draft.outgoingHost = "smtp.example.com"
        draft.incomingSecret = "incoming-secret"
        draft.outgoingSecret = "outgoing-secret"
        draft.signature = "Thanks"
        draft.summary = "Office"
        draft.aliases = [
            MailIdentity(accountID: draft.id, displayName: "Alias", emailAddress: "alias@example.com"),
        ]

        let saved = try await service.save(draft, existing: [])
        #expect(saved.count == 1)
        #expect(saved[0].details?.summary == "Office")
        #expect(await secrets.readSecret(for: draft.id, kind: .incomingPassword) == "incoming-secret")

        var loaded = try await service.draft(for: saved[0])
        #expect(loaded.incomingSecret.isEmpty)
        #expect(loaded.hasStoredIncomingSecret)
        #expect(loaded.signature == "Thanks")
        #expect(loaded.aliases.contains { $0.emailAddress == "alias@example.com" })
        #expect(loaded.aliases.contains { $0.emailAddress == "work@example.com" })

        loaded.displayName = "Work Updated"
        let updated = try await service.save(loaded, existing: saved)
        #expect(updated[0].displayName == "Work Updated")
        #expect(await secrets.readSecret(for: draft.id, kind: .incomingPassword) == "incoming-secret")
    }

    @Test func discoveryFillsPresetServers() throws {
        var draft = AccountDraft.makeNew()
        draft.emailAddress = "user@mail.ru"
        let preset = try #require(MailProviderPresets.preset(forDomain: "mail.ru"))
        let filled = draft.applyingDiscovery(
            MailAutoconfigResult(
                source: .preset,
                domain: "mail.ru",
                incomingCandidates: [preset.incoming],
                outgoing: preset.outgoing
            )
        )
        #expect(filled.incomingHost == "pop.mail.ru")
        #expect(filled.outgoingHost == "smtp.mail.ru")
        #expect(filled.displayName == "Mail.ru")
    }

    @Test func gmailDiscoveryCanUseAnAppPassword() throws {
        var draft = AccountDraft.makeNew()
        draft.emailAddress = "user@gmail.com"
        let preset = try #require(MailProviderPresets.preset(forDomain: "gmail.com"))
        draft = draft.applyingDiscovery(
            MailAutoconfigResult(
                source: .preset,
                domain: "gmail.com",
                incomingCandidates: [preset.incoming],
                outgoing: preset.outgoing
            )
        )
        #expect(draft.incomingAuthentication == .xoauth2)
        #expect(draft.outgoingAuthentication == .xoauth2)

        draft = draft.applyingCredentialChoice(.appPassword)
        let account = draft.makeAccount()
        #expect(account.incomingServer?.authentication == .userPassword)
        #expect(account.outgoingServer?.authentication == .userPassword)

        draft = draft.applyingCredentialChoice(.accessToken)
        #expect(draft.incomingAuthentication == .xoauth2)
        #expect(draft.outgoingAuthentication == .xoauth2)
    }

    @Test @MainActor func preferencesIgnoreUnknownFutureAndMissingKeys() throws {
        let suite = "SettingsPrefs.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let partial = #"{"unifyInboxes":false,"playSounds":false}"#
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: Data(partial.utf8))
        #expect(!decoded.unifyInboxes)
        #expect(decoded.includeSignature)
        #expect(decoded.showMenuBarIcon)
        #expect(decoded.markAsReadDelaySeconds == 0)

        let store = AppPreferencesStore(defaults: defaults)
        store.preferences.unifyInboxes = false
        store.preferences.composeFontSize = 18
        store.save()
        let reloaded = AppPreferencesStore(defaults: defaults)
        #expect(!reloaded.preferences.unifyInboxes)
        #expect(reloaded.preferences.composeFontSize == 18)
    }
}
