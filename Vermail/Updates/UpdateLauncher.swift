import AppKit
import Darwin
import Foundation

enum AppUpdateError: Error, LocalizedError {
    case feedFailed
    case downloadFailed
    case helperMissing
    case translocated
    case notWritable
    case staleDownload

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
        case .staleDownload:
            String(localized: "The downloaded update is not a newer version of Vermail.")
        }
    }
}

enum UpdateLauncher {
    static func install(_ release: AppRelease, onDownloadProgress: @escaping @Sendable (Double?) -> Void) async throws {
        try validateLocation()
        let directory = try updatesDirectory()
        let zip = try await download(release, into: directory, onProgress: onDownloadProgress)
        try requireExpectedVersion(zip, release.version)
        let jobURL = try writeJob(zip: zip, expectedVersion: release.version)
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
        let folder = UpdateJobLocation.file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func download(
        _ release: AppRelease,
        into directory: URL,
        onProgress: @escaping @Sendable (Double?) -> Void
    ) async throws -> URL {
        let (bytes, response) = try await openDownload(release.assetURL)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw AppUpdateError.downloadFailed
        }
        onProgress(nil)
        let destination = prepareArchive(in: directory, version: release.version)
        let fileManager = FileManager.default
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

    private static func openDownload(_ url: URL) async throws -> (URLSession.AsyncBytes, URLResponse) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 600)
        request.setValue("Vermail", forHTTPHeaderField: "User-Agent")
        return try await URLSession.shared.bytes(for: request)
    }

    /// A fixed name reused the previous archive. The last install put 0.9.7 back over a newer copy.
    private static func prepareArchive(in directory: URL, version: String) -> URL {
        let fileManager = FileManager.default
        let existing = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in existing where file.pathExtension.lowercased() == "zip" {
            try? fileManager.removeItem(at: file)
        }
        let safe = version.filter { $0.isNumber || $0 == "." }
        let name = safe.isEmpty ? "Vermail-macos.zip" : "Vermail-\(safe).zip"
        return directory.appending(path: name)
    }

    private static func requireExpectedVersion(_ zip: URL, _ expected: String) throws {
        let found = try UpdateReplacer.marketingVersion(inZip: zip)
        guard let incoming = AppVersionNumber(found),
              let wanted = AppVersionNumber(expected),
              incoming == wanted,
              AppUpdatePolicy.isNewer(found, than: AppVersion.marketing)
        else {
            throw AppUpdateError.staleDownload
        }
    }

    private static func writeJob(zip: URL, expectedVersion: String) throws -> URL {
        let job = UpdateJob(
            zipPath: zip.path(percentEncoded: false),
            destinationPath: Bundle.main.bundleURL.standardizedFileURL.path(percentEncoded: false),
            parentPID: ProcessInfo.processInfo.processIdentifier,
            expectedVersion: expectedVersion
        )
        try JSONEncoder().encode(job).write(to: UpdateJobLocation.file, options: .atomic)
        return UpdateJobLocation.file
    }

    private static func openHelper(jobURL _: URL) async throws {
        let helper = Bundle.main.bundleURL
            .appending(path: "Contents/Helpers/VermailUpdater.app", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: helper.path(percentEncoded: false)) else {
            throw AppUpdateError.helperMissing
        }
        // A sandboxed app cannot pass command-line arguments through Launch Services.
        // The helper reads UpdateJobLocation.file.
        let configuration = UpdateReplacer.foregroundLaunch()
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
