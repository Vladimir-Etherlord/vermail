import Foundation
import MailCore

public enum MailStorage {
    /// Root directory for the database and raw `.eml` files.
    public static func defaultRootDirectory(fileManager: FileManager = .default) throws -> URL {
        try fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Vermail", directoryHint: .isDirectory)
    }
}
