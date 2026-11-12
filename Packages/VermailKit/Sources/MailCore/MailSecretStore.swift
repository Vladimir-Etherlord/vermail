import Foundation
import Security

public enum AccountSecretKind: String, CaseIterable, Codable, Sendable {
    case incomingPassword
    case outgoingPassword
    case oauthAccessToken
    case oauthRefreshToken
}

public enum AccountSecretStoreError: Error, Equatable, Sendable {
    case unexpectedStatus(OSStatus)
    case invalidData
}

public protocol AccountSecretStore: Sendable {
    func saveSecret(_ secret: String, for accountID: UUID, kind: AccountSecretKind) async throws
    func readSecret(for accountID: UUID, kind: AccountSecretKind) async throws -> String?
    func deleteSecret(for accountID: UUID, kind: AccountSecretKind) async throws
}

public actor InMemorySecretStore: AccountSecretStore {
    private var storage: [String: String] = [:]

    public init() {}

    public func saveSecret(_ secret: String, for accountID: UUID, kind: AccountSecretKind) async {
        storage[key(accountID: accountID, kind: kind)] = secret
    }

    public func readSecret(for accountID: UUID, kind: AccountSecretKind) async -> String? {
        storage[key(accountID: accountID, kind: kind)]
    }

    public func deleteSecret(for accountID: UUID, kind: AccountSecretKind) async {
        storage.removeValue(forKey: key(accountID: accountID, kind: kind))
    }

    private func key(accountID: UUID, kind: AccountSecretKind) -> String {
        "\(accountID.uuidString).\(kind.rawValue)"
    }
}

public actor KeychainSecretStore: AccountSecretStore {
    private let serviceName: String

    public init(serviceName: String = "com.etherlord.vermail") {
        self.serviceName = serviceName
    }

    public func saveSecret(_ secret: String, for accountID: UUID, kind: AccountSecretKind) async throws {
        guard let data = secret.data(using: .utf8) else {
            throw AccountSecretStoreError.invalidData
        }
        let key = accountKey(accountID: accountID, kind: kind)

        var query = baseQuery(for: key)
        query[kSecValueData] = data

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return
        }

        if addStatus == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(
                baseQuery(for: key) as CFDictionary,
                [kSecValueData: data] as CFDictionary
            )
            if updateStatus == errSecSuccess {
                return
            }
            throw AccountSecretStoreError.unexpectedStatus(updateStatus)
        }

        throw AccountSecretStoreError.unexpectedStatus(addStatus)
    }

    public func readSecret(for accountID: UUID, kind: AccountSecretKind) async throws -> String? {
        let key = accountKey(accountID: accountID, kind: kind)
        var query = baseQuery(for: key)
        query[kSecReturnData] = kCFBooleanTrue
        query[kSecMatchLimit] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw AccountSecretStoreError.unexpectedStatus(status)
        }
        guard let data = item as? Data, let secret = String(data: data, encoding: .utf8) else {
            throw AccountSecretStoreError.invalidData
        }
        return secret
    }

    public func deleteSecret(for accountID: UUID, kind: AccountSecretKind) async throws {
        let key = accountKey(accountID: accountID, kind: kind)
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            return
        }
        throw AccountSecretStoreError.unexpectedStatus(status)
    }

    private func accountKey(accountID: UUID, kind: AccountSecretKind) -> String {
        "\(accountID.uuidString).\(kind.rawValue)"
    }

    private func baseQuery(for accountKey: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: accountKey,
        ]
    }
}
