import Foundation

struct AppPreferences: Equatable {
    var unifyInboxes: Bool = true
    var playSounds: Bool = true
    var showDockBadge: Bool = true
    var showMenuBarIcon: Bool = true
    var notificationsEnabled: Bool = true
    var markAsReadDelaySeconds: Double = 0
    var attachmentFolderPath: String?
    var attachmentFolderBookmark: Data?
    var defaultAccountID: UUID?
    var includeSignature: Bool = true
    var composeFontSize: Double = 13
    var showAvatars: Bool = true
    var showMessagePreview: Bool = true
    var confirmDelete: Bool = true
}

extension AppPreferences: Codable {
    private enum CodingKeys: String, CodingKey {
        case unifyInboxes
        case playSounds
        case showDockBadge
        case showMenuBarIcon
        case notificationsEnabled
        case markAsReadDelaySeconds
        case attachmentFolderPath
        case attachmentFolderBookmark
        case defaultAccountID
        case includeSignature
        case composeFontSize
        case showAvatars
        case showMessagePreview
        case confirmDelete
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        unifyInboxes = try container.decodeIfPresent(Bool.self, forKey: .unifyInboxes) ?? true
        playSounds = try container.decodeIfPresent(Bool.self, forKey: .playSounds) ?? true
        showDockBadge = try container.decodeIfPresent(Bool.self, forKey: .showDockBadge) ?? true
        showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        markAsReadDelaySeconds = try container.decodeIfPresent(Double.self, forKey: .markAsReadDelaySeconds) ?? 0
        attachmentFolderPath = try container.decodeIfPresent(String.self, forKey: .attachmentFolderPath)
        attachmentFolderBookmark = try container.decodeIfPresent(Data.self, forKey: .attachmentFolderBookmark)
        defaultAccountID = try container.decodeIfPresent(UUID.self, forKey: .defaultAccountID)
        includeSignature = try container.decodeIfPresent(Bool.self, forKey: .includeSignature) ?? true
        composeFontSize = try container.decodeIfPresent(Double.self, forKey: .composeFontSize) ?? 13
        showAvatars = try container.decodeIfPresent(Bool.self, forKey: .showAvatars) ?? true
        showMessagePreview = try container.decodeIfPresent(Bool.self, forKey: .showMessagePreview) ?? true
        confirmDelete = try container.decodeIfPresent(Bool.self, forKey: .confirmDelete) ?? true
    }
}

@MainActor
@Observable
final class AppPreferencesStore {
    private let defaults: UserDefaults
    private let key = "vermail.appPreferences"
    var preferences: AppPreferences

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(AppPreferences.self, from: data)
        {
            preferences = decoded
        } else {
            preferences = AppPreferences()
        }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: key)
    }

    func resolvedAttachmentFolder() -> URL? {
        guard let bookmark = preferences.attachmentFolderBookmark else { return nil }
        var stale = false
        return try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }
}
