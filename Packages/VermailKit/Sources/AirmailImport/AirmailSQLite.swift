import Foundation
import GRDB

struct AirmailTable {
    var name: String
    var columns: Set<String>
}

enum AirmailSQLite {
    static func openReadOnly(_ url: URL) throws -> DatabaseQueue? {
        guard FileManager.default.fileExists(atPath: url.fileSystemPath) else { return nil }
        do {
            return try open(url)
        } catch {
            if AirmailFiles.isPermission(error) {
                throw AirmailImportError.unreadableLibrary(url.fileSystemPath)
            }
            return try openImmutable(url)
        }
    }

    static func tables(in queue: DatabaseQueue) throws -> [AirmailTable] {
        try queue.read { database in
            let names = try String.fetchAll(
                database,
                sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table' AND name NOT LIKE 'sqlite%'
                """
            )
            return try names.map { name in
                try AirmailTable(name: name, columns: columnNames(database, table: name))
            }
        }
    }

    static func quote(_ name: String) -> String {
        "\"\(name.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func open(_ url: URL) throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.readonly = true
        configuration.busyMode = .timeout(5)
        return try DatabaseQueue(path: url.fileSystemPath, configuration: configuration)
    }

    private static func openImmutable(_ url: URL) throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.readonly = true
        let encoded = url.fileSystemPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? url
            .fileSystemPath
        return try DatabaseQueue(path: "file:\(encoded)?immutable=1", configuration: configuration)
    }

    private static func columnNames(_ database: Database, table: String) throws -> Set<String> {
        let rows = try Row.fetchAll(database, sql: "PRAGMA table_info(\(quote(table)))")
        return Set(rows.compactMap { row in
            let name: String = row["name"]
            return name.lowercased()
        })
    }
}

enum AirmailFiles {
    static func contents(of url: URL) throws -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            if isPermission(error) {
                throw AirmailImportError.unreadableLibrary(url.fileSystemPath)
            }
            throw error
        }
    }

    static func isPermission(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == 1 || nsError.code == 13 {
            return true
        }
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadNoPermissionError {
            return true
        }
        let text = String(describing: error).lowercased()
        return text.contains("operation not permitted") || text.contains("permission denied")
    }

    static func isAccountDirectory(_ url: URL) -> Bool {
        let data = url.appending(path: "Data.db")
        let messages = url.appending(path: "Message", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: data.fileSystemPath) {
            return true
        }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: messages.fileSystemPath, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}
