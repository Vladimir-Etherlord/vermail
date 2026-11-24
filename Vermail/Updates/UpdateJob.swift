import Foundation

struct UpdateJob: Codable, Equatable, Sendable {
    var zipPath: String
    var destinationPath: String
    var parentPID: Int32
}

enum UpdateJobLocation {
    /// Sandboxed Vermail cannot pass launch arguments to another app on this macOS.
    /// Both processes use this container path instead.
    static var file: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Containers/com.etherlord.vermail/Data/Library")
            .appending(path: "Application Support/Vermail/Updates/update-job.json")
    }
}

struct AppRelease: Equatable, Sendable {
    var version: String
    var notes: String
    var assetURL: URL
}

struct UpdatePrompt: Equatable, Sendable {
    var now: Date
    var current: String
    var release: AppRelease
    var manual: Bool
}
