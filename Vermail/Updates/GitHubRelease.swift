import Foundation

protocol UpdateFeed: Sendable {
    func latestRelease() async throws -> AppRelease?
}

struct GitHubReleaseFeed: UpdateFeed, Sendable {
    var endpoint = URL(string: "https://api.github.com/repos/Vladimir-Etherlord/vermail/releases/latest")!

    func latestRelease() async throws -> AppRelease? {
        var request = URLRequest(url: endpoint)
        request.setValue("Vermail", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppUpdateError.feedFailed }
        if http.statusCode == 404 {
            return nil
        }
        guard (200 ..< 300).contains(http.statusCode) else { throw AppUpdateError.feedFailed }
        return try GitHubReleaseParser.release(from: data)
    }
}

enum GitHubReleaseParser {
    static func release(from data: Data) throws -> AppRelease? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(GitHubReleaseDTO.self, from: data)
        guard let version = AppVersionNumber(decoded.tagName),
              let asset = preferredZip(decoded.assets) else { return nil }
        let notes = decoded.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return AppRelease(version: version.canonical, notes: notes, assetURL: asset.browserDownloadUrl)
    }

    private static func preferredZip(_ assets: [GitHubAssetDTO]) -> GitHubAssetDTO? {
        let zips = assets.filter { $0.name.lowercased().hasSuffix(".zip") }
        let preferred = zips.first { $0.name.compare("Vermail-macos.zip", options: .caseInsensitive) == .orderedSame }
        return preferred ?? zips.first
    }
}

private struct GitHubReleaseDTO: Decodable {
    var tagName: String
    var body: String?
    var assets: [GitHubAssetDTO]
}

private struct GitHubAssetDTO: Decodable {
    var name: String
    var browserDownloadUrl: URL
}
