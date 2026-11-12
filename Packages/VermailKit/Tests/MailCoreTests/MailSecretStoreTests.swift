import Foundation
import MailCore
import Testing

struct MailSecretStoreTests {
    @Test func inMemoryStoreRoundtrip() async throws {
        let store: any AccountSecretStore = InMemorySecretStore()
        let accountID = UUID()

        try await store.saveSecret("s3cr3t", for: accountID, kind: .incomingPassword)
        let read = try await store.readSecret(for: accountID, kind: .incomingPassword)
        #expect(read == "s3cr3t")

        try await store.deleteSecret(for: accountID, kind: .incomingPassword)
        let deleted = try await store.readSecret(for: accountID, kind: .incomingPassword)
        #expect(deleted == nil)
    }

    @Test func secretKindsAreIndependent() async throws {
        let store: any AccountSecretStore = InMemorySecretStore()
        let accountID = UUID()

        try await store.saveSecret("password", for: accountID, kind: .incomingPassword)
        try await store.saveSecret("refresh", for: accountID, kind: .oauthRefreshToken)

        #expect(try await store.readSecret(for: accountID, kind: .incomingPassword) == "password")
        #expect(try await store.readSecret(for: accountID, kind: .oauthRefreshToken) == "refresh")
    }
}
