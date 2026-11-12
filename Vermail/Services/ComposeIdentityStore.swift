import Foundation
import MailCore

struct MailIdentity: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var accountID: UUID
    var displayName: String
    var emailAddress: String

    init(id: UUID = UUID(), accountID: UUID, displayName: String, emailAddress: String) {
        self.id = id
        self.accountID = accountID
        self.displayName = displayName
        self.emailAddress = emailAddress
    }
}

struct ComposeIdentityStore: Sendable {
    private struct FileContents: Codable {
        var identities: [MailIdentity]
        var signatures: [String: String]
    }

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first ?? FileManager.default.temporaryDirectory
            self.fileURL = appSupport
                .appending(path: "Vermail", directoryHint: .isDirectory)
                .appending(path: "compose.json")
        }
    }

    func identities(for accounts: [MailAccount]) throws -> [MailIdentity] {
        var contents = try load()
        var changed = false
        for account in accounts {
            let exists = contents.identities.contains { identity in
                identity.accountID == account.id &&
                    identity.emailAddress.caseInsensitiveCompare(account.emailAddress) == .orderedSame
            }
            if !exists {
                contents.identities.append(
                    MailIdentity(
                        accountID: account.id,
                        displayName: account.displayName,
                        emailAddress: account.emailAddress
                    )
                )
                changed = true
            }
        }
        if changed {
            try save(contents)
        }
        let accountIDs = Set(accounts.map(\.id))
        return contents.identities.filter { accountIDs.contains($0.accountID) }
    }

    func signature(for accountID: UUID) throws -> String {
        try load().signatures[accountID.uuidString] ?? ""
    }

    func setSignature(_ signature: String, for accountID: UUID) throws {
        var contents = try load()
        contents.signatures[accountID.uuidString] = signature
        try save(contents)
    }

    func addIdentity(_ identity: MailIdentity) throws {
        var contents = try load()
        contents.identities.append(identity)
        try save(contents)
    }

    func replaceIdentities(_ identities: [MailIdentity], for accountID: UUID, signature: String) throws {
        var contents = try load()
        contents.identities.removeAll { $0.accountID == accountID }
        contents.identities.append(contentsOf: identities)
        contents.signatures[accountID.uuidString] = signature
        try save(contents)
    }

    func removeAccount(_ accountID: UUID) throws {
        var contents = try load()
        contents.identities.removeAll { $0.accountID == accountID }
        contents.signatures.removeValue(forKey: accountID.uuidString)
        try save(contents)
    }

    private func load() throws -> FileContents {
        guard FileManager.default.fileExists(atPath: fileURL.path()) else {
            return FileContents(identities: [], signatures: [:])
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(FileContents.self, from: data)
    }

    private func save(_ contents: FileContents) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(contents).write(to: fileURL, options: .atomic)
    }
}
