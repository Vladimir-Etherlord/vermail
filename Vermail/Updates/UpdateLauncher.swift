import AppKit
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
    static func install(_ release: AppRelease) async throws {
        try validateLocation()
        let directory = try updatesDirectory()
        let zip = try await download(release.assetURL, into: directory)
        let jobURL = try writeJob(zip: zip, into: directory)
        try await openHelper(jobURL: jobURL)
    }

    private static func validateLocation() throws {
        let bundle = Bundle.main.bundleURL.path(percentEncoded: false)
        if bundle.contains("AppTranslocation") {
            throw AppUpdateError.translocated
        }
        let parent = Bundle.main.bundleURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path(percentEncoded: false)) else {
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

    private static func download(_ url: URL, into directory: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue("Vermail", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 600
        let (temporary, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw AppUpdateError.downloadFailed
        }
        let destination = directory.appending(path: "Vermail-macos.zip")
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporary, to: destination)
        return destination
    }

    private static func writeJob(zip: URL, into directory: URL) throws -> URL {
        let job = UpdateJob(
            zipPath: zip.path(percentEncoded: false),
            destinationPath: Bundle.main.bundleURL.path(percentEncoded: false),
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
        try await NSWorkspace.shared.openApplication(at: helper, configuration: configuration)
    }
}
