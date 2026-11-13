import Foundation
import MailCore

/// Moves a mailbox that was stored in the temporary directory into Application Support.
enum StorageBootstrap {
    static func adoptFallbackMailbox(
        into root: URL,
        fallbackRoot: URL,
        fileManager: FileManager = .default
    ) throws {
        let destination = root.appending(path: "storage.sqlite")
        guard fileManager.fileExists(atPath: destination.fileSystemPath) == false else { return }

        let source = fallbackRoot.appending(path: "storage.sqlite")
        guard fileManager.fileExists(atPath: source.fileSystemPath) else { return }

        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["storage.sqlite", "storage.sqlite-wal", "storage.sqlite-shm"] {
            let from = fallbackRoot.appending(path: name)
            guard fileManager.fileExists(atPath: from.fileSystemPath) else { continue }
            try fileManager.copyItem(at: from, to: root.appending(path: name))
        }
        try copyRawMessages(from: fallbackRoot, to: root, fileManager: fileManager)
    }

    private static func copyRawMessages(from fallbackRoot: URL, to root: URL, fileManager: FileManager) throws {
        let source = fallbackRoot.appending(path: "raw", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: source.fileSystemPath) else { return }

        let destination = root.appending(path: "raw", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let children = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        for child in children {
            let target = destination.appending(path: child.lastPathComponent, directoryHint: .isDirectory)
            guard fileManager.fileExists(atPath: target.fileSystemPath) == false else { continue }
            try fileManager.copyItem(at: child, to: target)
        }
    }
}
