import Foundation
import MailCore
import MailStorage

public enum AirmailImportCommand {
    public static func run(_ arguments: [String]) async -> Int32 {
        do {
            let options = try AirmailImportOptions.parse(arguments)
            if options.help {
                print(helpText)
                return 0
            }
            let report = try await execute(options)
            print(reportText(report, options: options))
            return report.failed == 0 ? 0 : 1
        } catch let error as AirmailImportError {
            fputs(error.description + "\n", stderr)
            return 1
        } catch {
            fputs(String(describing: error) + "\n", stderr)
            return 1
        }
    }

    static func execute(_ options: AirmailImportOptions) async throws -> AirmailImportReport {
        let library = AirmailLibrary(root: AirmailLocations.airmailRoot(override: options.airmailRoot))
        _ = try library.accountEmails()
        let root = AirmailLocations.vermailRoot(override: options.vermailRoot)
        let accounts = try loadAccounts(root)
        let database = try MailDatabase(rootDirectory: root)
        return try await AirmailImporter.importMail(
            from: library,
            into: database,
            accounts: accounts,
            accountEmail: options.accountEmail,
            dryRun: options.dryRun
        )
    }

    private static func loadAccounts(_ root: URL) throws -> [MailAccount] {
        let url = root.appending(path: "accounts.json")
        guard FileManager.default.fileExists(atPath: url.fileSystemPath) else {
            throw AirmailImportError.noVermailAccounts(root.fileSystemPath)
        }
        let data = try Data(contentsOf: url)
        let accounts = try JSONDecoder().decode([MailAccount].self, from: data)
        if accounts.isEmpty {
            throw AirmailImportError.noVermailAccounts(root.fileSystemPath)
        }
        return accounts
    }

    private static func reportText(_ report: AirmailImportReport, options: AirmailImportOptions) -> String {
        let airmail = AirmailLocations.airmailRoot(override: options.airmailRoot).fileSystemPath
        let vermail = AirmailLocations.vermailRoot(override: options.vermailRoot).fileSystemPath
        let mode = options.dryRun ? "Dry run\n" : ""
        return """
        \(mode)Airmail: \(airmail)
        Vermail: \(vermail)
        Scanned \(report.scanned)
        Imported \(report.imported)
        Already present \(report.alreadyPresent)
        Skipped \(report.skippedEmpty)
        Failed \(report.failed)
        """
    }
}

struct AirmailImportOptions: Equatable {
    var airmailRoot: URL?
    var vermailRoot: URL?
    var accountEmail: String?
    var dryRun = false
    var help = false

    static func parse(_ arguments: [String]) throws -> AirmailImportOptions {
        var options = AirmailImportOptions()
        var index = 1
        while index < arguments.count {
            let flag = arguments[index]
            index += 1
            try apply(flag, arguments: arguments, index: &index, options: &options)
        }
        return options
    }

    private static func apply(
        _ flag: String,
        arguments: [String],
        index: inout Int,
        options: inout AirmailImportOptions
    ) throws {
        switch flag {
        case "--help", "-h":
            options.help = true
        case "--dry-run":
            options.dryRun = true
        case "--airmail-root":
            options.airmailRoot = try URL(fileURLWithPath: value(arguments, index: &index), isDirectory: true)
        case "--vermail-root":
            options.vermailRoot = try URL(fileURLWithPath: value(arguments, index: &index), isDirectory: true)
        case "--account-email":
            options.accountEmail = try value(arguments, index: &index)
        default:
            throw AirmailImportError.invalidArguments(flag)
        }
    }

    private static func value(_ arguments: [String], index: inout Int) throws -> String {
        guard index < arguments.count else {
            throw AirmailImportError.invalidArguments("missing value")
        }
        let value = arguments[index]
        index += 1
        return value
    }
}

private let helpText = """
airmail-import [--dry-run] [--airmail-root PATH] [--vermail-root PATH] [--account-email ADDRESS]

Copy messages stored by Airmail into Vermail. Messages already stored, including copies
with the same Message-ID, are left in place. The command prints counts only.
"""
