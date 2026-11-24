import AppKit
import Darwin
import Foundation

enum AppUpdateError: Error, LocalizedError {
    case feedFailed
    case downloadFailed
    case helperMissing
    case translocated
    case notWritable

    var errorDescription: String? {
        switch self {
        case .feedFailed:
            String(localized: "Couldn't check for updates.")
        case .downloadFailed:
            String(localized: "The update could not be downloaded.")
        case .helperMissing:
            String(localized: "This copy of Vermail does not include the updater.")
        case .translocated:
            String(localized: "Move Vermail into the Applications folder, then update it.")
        case .notWritable:
            String(localized: "Vermail cannot replace itself in this folder.")
        }
    }
}

enum UpdateLauncher {
    static func install(_ release: AppRelease, onDownloadProgress: @escaping @Sendable (Double?) -> Void) async throws {
        try validateLocation()
        let directory = try updatesDirectory()
        let zip = try await download(release.assetURL, into: directory, onProgress: onDownloadProgress)
        let jobURL = try writeJob(zip: zip, into: directory)
        try await openHelper(jobURL: jobURL)
    }

    private static func validateLocation() throws {
        let bundle = Bundle.main.bundleURL.path(percentEncoded: false)
        if bundle.contains("AppTranslocation") {
            throw AppUpdateError.translocated
        }
        let parent = Bundle.main.bundleURL.deletingLastPathComponent().path(percentEncoded: false)
        // Sandbox hides writes outside the container. The updater is outside it and uses the user's rights.
        guard UpdateLocation.userCanWrite(parent) else {
            throw AppUpdateError.notWritable
        }
    }

    private static func updatesDirectory() throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = root.appending(path: "Vermail/Updates", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func download(
        _ url: URL,
        into directory: URL,
        onProgress: @escaping @Sendable (Double?) -> Void
    ) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue("Vermail", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 600
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw AppUpdateError.downloadFailed
        }
        onProgress(nil)
        let destination = directory.appending(path: "Vermail-macos.zip")
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destination)
        }
        fileManager.createFile(atPath: destination.path(percentEncoded: false), contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer {
            try? handle.close()
        }

        let expected = response.expectedContentLength
        var received: Int64 = 0
        var buffer: [UInt8] = []
        buffer.reserveCapacity(64 * 1024)

        for try await byte in bytes {
            buffer.append(byte)
            received += 1
            if buffer.count >= 64 * 1024 {
                try handle.write(contentsOf: Data(buffer))
                buffer.removeAll(keepingCapacity: true)
            }
            if expected > 0, received.isMultiple(of: 16 * 1024) {
                let ratio = min(max(Double(received) / Double(expected), 0), 1)
                onProgress(ratio)
            }
        }

        if !buffer.isEmpty {
            try handle.write(contentsOf: Data(buffer))
        }
        if expected > 0 {
            onProgress(1)
        }
        return destination
    }

    private static func writeJob(zip: URL, into directory: URL) throws -> URL {
        let job = UpdateJob(
            zipPath: zip.path(percentEncoded: false),
            destinationPath: Bundle.main.bundleURL.standardizedFileURL.path(percentEncoded: false),
            parentPID: ProcessInfo.processInfo.processIdentifier
        )
        let url = directory.appending(path: "update-job.json")
        try JSONEncoder().encode(job).write(to: url, options: .atomic)
        return url
    }

    private static func openHelper(jobURL: URL) async throws {
        let helper = Bundle.main.bundleURL
            .appending(path: "Contents/Helpers/VermailUpdater.app", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: helper.path(percentEncoded: false)) else {
            throw AppUpdateError.helperMissing
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = [jobURL.path(percentEncoded: false)]
        configuration.createsNewApplicationInstance = true
        // Launch Services may not report the helper as launched until it exits.
        // Waiting for that report would deadlock with the helper's own wait.
        NSWorkspace.shared.openApplication(at: helper, configuration: configuration) { _, _ in }
        try await Task.sleep(for: .seconds(1))
    }
}

enum UpdateLocation {
    /// POSIX write access of the current user. Owner rights win, then a matching group, then others.
    static func userCanWrite(_ path: String) -> Bool {
        var info = stat()
        guard path.withCString({ stat($0, &info) }) == 0 else { return false }
        let mode = info.st_mode
        if info.st_uid == getuid() {
            return (mode & S_IWUSR) != 0
        }
        if (mode & S_IWGRP) != 0, belongsToGroup(info.st_gid) {
            return true
        }
        return (mode & S_IWOTH) != 0
    }

    private static func belongsToGroup(_ group: gid_t) -> Bool {
        if group == getgid() || group == getegid() {
            return true
        }
        var groups = [gid_t](repeating: 0, count: Int(NGROUPS_MAX))
        let count = getgroups(Int32(groups.count), &groups)
        guard count > 0 else { return false }
        return groups.prefix(Int(count)).contains(group)
    }
}
