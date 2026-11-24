import Foundation
import Testing
@testable import Vermail

struct AppUpdateTests {
    @Test func versionsCompareNumericallyAndIgnoreALeadingV() throws {
        let current = try #require(AppVersionNumber("0.9.0"))
        let patch = try #require(AppVersionNumber("v0.9.1"))
        let minor = try #require(AppVersionNumber("0.10.0"))
        #expect(current < patch)
        #expect(patch < minor)
        #expect(patch == AppVersionNumber("0.9.1"))
        #expect(AppVersionNumber("0.9") == AppVersionNumber("0.9.0"))
        #expect(AppVersionNumber("later") == nil)
    }

    @Test func checksFollowTheIntervalAndTheSkipAndRemindChoices() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var preferences = AppPreferences()
        #expect(AppUpdatePolicy.shouldCheck(preferences, now: now))
        preferences.lastUpdateCheckAt = now
        #expect(!AppUpdatePolicy.shouldCheck(preferences, now: now.addingTimeInterval(3600)))
        let due = now.addingTimeInterval(AppUpdatePolicy.day)
        #expect(AppUpdatePolicy.shouldCheck(preferences, now: due))

        let release = try sampleRelease("0.9.1")
        var prompt = UpdatePrompt(now: due, current: "0.9.0", release: release, manual: false)
        #expect(AppUpdatePolicy.shouldPrompt(preferences, prompt))
        preferences.skippedUpdateVersion = "0.9.1"
        #expect(!AppUpdatePolicy.shouldPrompt(preferences, prompt))
        prompt.manual = true
        #expect(AppUpdatePolicy.shouldPrompt(preferences, prompt))

        preferences.skippedUpdateVersion = nil
        preferences.pendingUpdateVersion = "0.9.1"
        preferences.updateRemindAfter = due.addingTimeInterval(AppUpdatePolicy.day)
        prompt.manual = false
        #expect(!AppUpdatePolicy.shouldPrompt(preferences, prompt))
        prompt.now = preferences.updateRemindAfter ?? due
        #expect(AppUpdatePolicy.shouldPrompt(preferences, prompt))
        preferences.checkForUpdates = false
        #expect(!AppUpdatePolicy.shouldCheck(preferences, now: due))
    }

    @Test func releaseParserPrefersTheVermailArchive() throws {
        let parsed = try GitHubReleaseParser.release(from: Data(releaseJSON.utf8))
        let release = try #require(parsed)
        #expect(release.version == "0.10.0")
        #expect(release.notes == "Fixes")
        #expect(release.assetURL.absoluteString == "https://example.com/Vermail-macos.zip")
        let notes = #"{"tag_name":"build","body":"","assets":[]}"#
        #expect(try GitHubReleaseParser.release(from: Data(notes.utf8)) == nil)
    }

    @Test func oldPreferencesKeepUpdateChecksEnabled() throws {
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: Data("{}".utf8))
        #expect(decoded.checkForUpdates)
        #expect(decoded.updateCheckIntervalDays == 1)
        #expect(decoded.pendingUpdateVersion == nil)
    }

    @Test func archiveContainsTheApplicationBundle() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "VermailUpdate-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let packed = try makeArchive(at: root, marker: "new")
        let unpacked = root.appending(path: "unpacked", directoryHint: .isDirectory)
        try UpdateReplacer.unzip(packed, into: unpacked)
        let application = try #require(UpdateReplacer.application(in: unpacked))
        let marker = application.appending(path: "Contents/Marker.txt")
        #expect(try String(contentsOf: marker, encoding: .utf8) == "new")
    }

    private func sampleRelease(_ version: String) throws -> AppRelease {
        let url = try #require(URL(string: "https://example.com/\(version).zip"))
        return AppRelease(version: version, notes: "", assetURL: url)
    }

    private func makeArchive(at root: URL, marker: String) throws -> URL {
        let contents = root.appending(path: "src/Vermail.app/Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try Data(marker.utf8).write(to: contents.appending(path: "Marker.txt"))
        let zip = root.appending(path: "Vermail-macos.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [
            "-c", "-k", "--keepParent",
            root.appending(path: "src/Vermail.app").path(percentEncoded: false),
            zip.path(percentEncoded: false),
        ]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return zip
    }

    private let releaseJSON = """
    {"tag_name":"v0.10.0","body":"Fixes\\n","assets":[
    {"name":"notes.txt","browser_download_url":"https://example.com/notes.txt"},
    {"name":"other.zip","browser_download_url":"https://example.com/other.zip"},
    {"name":"Vermail-macos.zip","browser_download_url":"https://example.com/Vermail-macos.zip"}]}
    """
}
