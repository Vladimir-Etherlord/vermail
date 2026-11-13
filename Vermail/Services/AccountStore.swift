import Foundation
import MailCore

public final class AccountStore: Sendable {
    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first ?? FileManager.default.temporaryDirectory
            self.fileURL = appSupport
                .appending(path: "Vermail", directoryHint: .isDirectory)
                .appending(path: "accounts.json")
        }
    }

    public func loadAccounts() throws -> [MailAccount] {
        guard FileManager.default.fileExists(atPath: fileURL.fileSystemPath) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([MailAccount].self, from: data)
    }

    public func saveAccounts(_ accounts: [MailAccount]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(accounts)
        try data.write(to: fileURL, options: .atomic)
    }
}
