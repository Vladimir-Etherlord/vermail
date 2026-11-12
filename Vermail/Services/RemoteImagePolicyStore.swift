import Foundation

@MainActor
final class RemoteImagePolicyStore {
    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "vermail.remoteImageAllowedSenders"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func isAlwaysAllowed(sender: String?) -> Bool {
        guard let email = Self.extractEmailAddress(from: sender) else {
            return false
        }
        return allowedSenders().contains(email)
    }

    func allowAlways(sender: String?) {
        guard let email = Self.extractEmailAddress(from: sender) else {
            return
        }
        var current = allowedSenders()
        current.insert(email)
        defaults.set(Array(current).sorted(), forKey: storageKey)
    }

    func allowedSenders() -> Set<String> {
        let array = defaults.stringArray(forKey: storageKey) ?? []
        return Set(array.map { $0.lowercased() })
    }

    static func extractEmailAddress(from raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let start = trimmed.firstIndex(of: "<"),
           let end = trimmed[start...].firstIndex(of: ">")
        {
            let inside = trimmed[trimmed.index(after: start) ..< end]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return inside.isEmpty ? nil : inside
        }

        return trimmed.lowercased()
    }

    static func containsRemoteImages(in html: String?) -> Bool {
        guard let html, !html.isEmpty else { return false }
        let pattern = #"(?i)(?:<img\b[^>]*\bsrc\s*=|\burl\s*\()\s*['"]?\s*https?://"#
        return html.range(of: pattern, options: .regularExpression) != nil
    }
}
