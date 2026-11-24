import Foundation

struct AppPreferences: Equatable {
    var unifyInboxes: Bool = true
    var playSounds: Bool = true
    var showDockBadge: Bool = true
    var showMenuBarIcon: Bool = true
    var notificationsEnabled: Bool = true
    var markAsReadDelaySeconds: Double = 0
    var defaultAccountID: UUID?
    var includeSignature: Bool = true
    var composeFontSize: Double = 13
    var showAvatars: Bool = true
    var showMessagePreview: Bool = true
    var confirmDelete: Bool = true
    var checkForUpdates: Bool = true
    var updateCheckIntervalDays: Int = 1
    var skippedUpdateVersion: String?
    var updateRemindAfter: Date?
    var lastUpdateCheckAt: Date?
    var pendingUpdateVersion: String?
    var pendingUpdateNotes: String?
    var pendingUpdateURL: String?
}

extension AppPreferences: Codable {
    private enum CodingKeys: String, CodingKey {
        case unifyInboxes
        case playSounds
        case showDockBadge
        case showMenuBarIcon
        case notificationsEnabled
        case markAsReadDelaySeconds
        case defaultAccountID
        case includeSignature
        case composeFontSize
        case showAvatars
        case showMessagePreview
        case confirmDelete
        case checkForUpdates
        case updateCheckIntervalDays
        case skippedUpdateVersion
        case updateRemindAfter
        case lastUpdateCheckAt
        case pendingUpdateVersion
        case pendingUpdateNotes
        case pendingUpdateURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        unifyInboxes = try container.decodeIfPresent(Bool.self, forKey: .unifyInboxes) ?? true
        playSounds = try container.decodeIfPresent(Bool.self, forKey: .playSounds) ?? true
        showDockBadge = try container.decodeIfPresent(Bool.self, forKey: .showDockBadge) ?? true
        showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        markAsReadDelaySeconds = try container.decodeIfPresent(Double.self, forKey: .markAsReadDelaySeconds) ?? 0
        defaultAccountID = try container.decodeIfPresent(UUID.self, forKey: .defaultAccountID)
        includeSignature = try container.decodeIfPresent(Bool.self, forKey: .includeSignature) ?? true
        composeFontSize = try container.decodeIfPresent(Double.self, forKey: .composeFontSize) ?? 13
        showAvatars = try container.decodeIfPresent(Bool.self, forKey: .showAvatars) ?? true
        showMessagePreview = try container.decodeIfPresent(Bool.self, forKey: .showMessagePreview) ?? true
        confirmDelete = try container.decodeIfPresent(Bool.self, forKey: .confirmDelete) ?? true
        checkForUpdates = try container.decodeIfPresent(Bool.self, forKey: .checkForUpdates) ?? true
        let days = try container.decodeIfPresent(Int.self, forKey: .updateCheckIntervalDays) ?? 1
        updateCheckIntervalDays = max(1, days)
        skippedUpdateVersion = try container.decodeIfPresent(String.self, forKey: .skippedUpdateVersion)
        updateRemindAfter = try container.decodeIfPresent(Date.self, forKey: .updateRemindAfter)
        lastUpdateCheckAt = try container.decodeIfPresent(Date.self, forKey: .lastUpdateCheckAt)
        pendingUpdateVersion = try container.decodeIfPresent(String.self, forKey: .pendingUpdateVersion)
        pendingUpdateNotes = try container.decodeIfPresent(String.self, forKey: .pendingUpdateNotes)
        pendingUpdateURL = try container.decodeIfPresent(String.self, forKey: .pendingUpdateURL)
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
}
