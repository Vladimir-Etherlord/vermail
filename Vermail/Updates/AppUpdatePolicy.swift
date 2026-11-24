import Foundation

enum AppUpdatePolicy {
    static let day: TimeInterval = 24 * 60 * 60

    static func intervalDays(_ preferences: AppPreferences) -> Int {
        max(1, preferences.updateCheckIntervalDays)
    }

    static func shouldCheck(_ preferences: AppPreferences, now: Date) -> Bool {
        guard preferences.checkForUpdates else { return false }
        guard let last = preferences.lastUpdateCheckAt else { return true }
        let next = last.addingTimeInterval(TimeInterval(intervalDays(preferences)) * day)
        return now >= next
    }

    static func shouldPrompt(_ preferences: AppPreferences, _ prompt: UpdatePrompt) -> Bool {
        guard isNewer(prompt.release.version, than: prompt.current) else { return false }
        if prompt.manual {
            return true
        }
        guard preferences.checkForUpdates else { return false }
        if preferences.skippedUpdateVersion == prompt.release.version {
            return false
        }
        if preferences.pendingUpdateVersion == prompt.release.version,
           let remind = preferences.updateRemindAfter, prompt.now < remind
        {
            return false
        }
        return true
    }

    static func isNewer(_ latest: String, than current: String) -> Bool {
        guard let latestVersion = AppVersionNumber(latest), let currentVersion = AppVersionNumber(current) else {
            return false
        }
        return latestVersion > currentVersion
    }

    static func storedRelease(_ preferences: AppPreferences) -> AppRelease? {
        guard let version = preferences.pendingUpdateVersion,
              let urlString = preferences.pendingUpdateURL,
              let url = URL(string: urlString)
        else { return nil }
        return AppRelease(version: version, notes: preferences.pendingUpdateNotes ?? "", assetURL: url)
    }
}
