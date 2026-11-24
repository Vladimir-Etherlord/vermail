import Foundation

struct UpdateJob: Codable, Equatable, Sendable {
    var zipPath: String
    var destinationPath: String
    var parentPID: Int32
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
