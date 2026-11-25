import AppKit
import Foundation

enum UpdateReplaceError: Error, LocalizedError, Sendable {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(details):
            details.isEmpty ? "The update could not be installed." : details
        }
    }
}

/// Replaces a `Vermail.app` bundle after the processes that are using it have exited.
enum UpdateReplacer {
    static func unzip(_ zip: URL, into directory: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.path(percentEncoded: false)) {
            try fileManager.removeItem(at: directory)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try run(
            "/usr/bin/ditto",
            ["-x", "-k", zip.path(percentEncoded: false), directory.path(percentEncoded: false)]
        )
    }

    static func marketingVersion(of application: URL) -> String? {
        let plist = application.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist) else { return nil }
        return marketingVersion(inPlist: data)
    }

    static func marketingVersion(inZip zip: URL) throws -> String {
        let data = try runOutput(
            "/usr/bin/unzip",
            ["-p", zip.path(percentEncoded: false), "Vermail.app/Contents/Info.plist"]
        )
        guard let version = marketingVersion(inPlist: data) else {
            throw UpdateReplaceError.commandFailed("The update archive does not contain Vermail.")
        }
        return version
    }

    /// Refuses a cached or mismatched archive before the running copy is replaced.
    static func validateInstall(application: URL, expectedVersion: String?, replacing destination: URL) throws {
        guard let found = marketingVersion(of: application) else {
            throw UpdateReplaceError.commandFailed("The update archive does not contain Vermail.")
        }
        try requireMatch(found, expected: expectedVersion)
        try requireNewer(found, than: destination)
    }

    static func centeredFrame(size: NSSize, visible: NSRect) -> NSRect {
        NSRect(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    @MainActor
    static func placeInCenter(_ window: NSWindow) {
        let screen = NSApp.mainWindow?.screen
            ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            window.center()
            return
        }
        window.setFrame(centeredFrame(size: window.frame.size, visible: visible), display: true)
    }

    static func application(in directory: URL) -> URL? {
        let fileManager = FileManager.default
        if let found = bundle(in: directory, fileManager: fileManager) {
            return found
        }
        guard let children = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return nil }
        return children.compactMap { bundle(in: $0, fileManager: fileManager) }.first
    }

    static func bundleIsInsideHostApplication(_ bundle: URL) -> Bool {
        bundle.standardizedFileURL.path.contains("/Vermail.app/Contents/Helpers/")
    }

    /// Launch Services opens a normal foreground app. `activates` is required so macOS does not
    /// leave the new process running without windows.
    static func foregroundLaunch() -> NSWorkspace.OpenConfiguration {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        configuration.hides = false
        configuration.addsToRecentItems = false
        return configuration
    }

    static func temporaryCopy(of bundle: URL) throws -> URL {
        let copy = FileManager.default.temporaryDirectory
            .appending(path: "VermailUpdater-\(UUID().uuidString).app", directoryHint: .isDirectory)
        try run("/usr/bin/ditto", [bundle.path(percentEncoded: false), copy.path(percentEncoded: false)])
        clearQuarantine(copy)
        return copy
    }

    /// Replaces `destination` from a process that is not running inside it.
    static func install(application: URL, replacing destination: URL) throws {
        let updater = Bundle.main.bundleIdentifier == "com.etherlord.vermail.updater"
        if updater, bundleIsInsideHostApplication(Bundle.main.bundleURL) {
            throw UpdateReplaceError.commandFailed("The updater is still inside the application.")
        }
        let parent = destination.deletingLastPathComponent()
        let staging = parent.appending(path: ".\(destination.lastPathComponent).incoming", directoryHint: .isDirectory)
        let previous = parent.appending(path: ".\(destination.lastPathComponent).previous", directoryHint: .isDirectory)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: staging.path(percentEncoded: false)) {
            try fileManager.removeItem(at: staging)
        }
        if fileManager.fileExists(atPath: previous.path(percentEncoded: false)) {
            try fileManager.removeItem(at: previous)
        }
        try run("/usr/bin/ditto", [application.path(percentEncoded: false), staging.path(percentEncoded: false)])
        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            try fileManager.moveItem(at: destination, to: previous)
        }
        do {
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            if fileManager.fileExists(atPath: previous.path(percentEncoded: false)) {
                try? fileManager.moveItem(at: previous, to: destination)
            }
            throw error
        }
        if fileManager.fileExists(atPath: previous.path(percentEncoded: false)) {
            try? fileManager.removeItem(at: previous)
        }
        clearQuarantine(destination)
    }

    private static func marketingVersion(inPlist data: Data) -> String? {
        guard let object = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let version = object["CFBundleShortVersionString"] as? String
        else { return nil }
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func requireMatch(_ found: String, expected: String?) throws {
        guard let expected, !expected.isEmpty else { return }
        guard let incoming = AppVersionNumber(found),
              let wanted = AppVersionNumber(expected),
              incoming == wanted
        else {
            throw UpdateReplaceError.commandFailed("The downloaded update is not the expected version.")
        }
    }

    private static func requireNewer(_ found: String, than destination: URL) throws {
        guard let installed = marketingVersion(of: destination),
              let incoming = AppVersionNumber(found),
              let current = AppVersionNumber(installed)
        else { return }
        guard incoming > current else {
            throw UpdateReplaceError.commandFailed("The downloaded update is not newer than this copy.")
        }
    }

    private static func bundle(in directory: URL, fileManager: FileManager) -> URL? {
        let candidate = directory.appending(path: "Vermail.app", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: candidate.path(percentEncoded: false)) else { return nil }
        return candidate
    }

    private static func clearQuarantine(_ url: URL) {
        try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", url.path(percentEncoded: false)])
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        _ = try runOutput(tool, arguments)
    }

    @discardableResult
    private static func runOutput(_ tool: String, _ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let details = errors.fileHandleForReading.readDataToEndOfFile()
            throw UpdateReplaceError.commandFailed(String(decoding: details, as: UTF8.self))
        }
        return data
    }
}
