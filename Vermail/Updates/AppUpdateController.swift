import AppKit
import Foundation

enum UpdatePhase: Equatable {
    case ready
    case downloading
    case installing
    case failed(String)
}

@MainActor
@Observable
final class AppUpdateController {
    static let shared = AppUpdateController()

    private(set) var release: AppRelease?
    private(set) var phase: UpdatePhase = .ready
    private(set) var downloadProgress: Double?
    private var running: Task<String, Never>?
    private var installTask: Task<Void, Never>?
    private var didChoose = false
    private var store: AppPreferencesStore?
    private let feed: any UpdateFeed
    private let windows = UpdateWindowController()

    init(feed: any UpdateFeed = GitHubReleaseFeed()) {
        self.feed = feed
    }

    var isBusy: Bool {
        phase == .downloading || phase == .installing
    }

    var failureMessage: String? {
        if case let .failed(message) = phase {
            return message
        }
        return nil
    }

    var statusLine: String {
        switch phase {
        case .downloading:
            String(localized: "Downloading the update…")
        case .installing:
            String(localized: "Installing the update. Vermail will reopen in a moment.")
        case .ready, .failed:
            ""
        }
    }

    func checkIfDue(store: AppPreferencesStore, now: Date = .now) async {
        self.store = store
        let preferences = store.preferences
        if AppUpdatePolicy.shouldCheck(preferences, now: now) {
            _ = await runCheck(store: store, now: now, manual: false)
        } else if let release = AppUpdatePolicy.storedRelease(preferences) {
            let prompt = UpdatePrompt(now: now, current: AppVersion.marketing, release: release, manual: false)
            if AppUpdatePolicy.shouldPrompt(preferences, prompt) {
                present(release)
            }
        }
    }

    func checkNow(store: AppPreferencesStore) async -> String {
        self.store = store
        return await runCheck(store: store, now: .now, manual: true)
    }

    func remindLater() {
        guard !didChoose else { return }
        didChoose = true
        saveRemind()
        windows.close()
    }

    func skipThisVersion() {
        guard !didChoose, let release else { return }
        didChoose = true
        guard var preferences = store?.preferences else { return }
        preferences.skippedUpdateVersion = release.version
        preferences.updateRemindAfter = nil
        store?.preferences = preferences
        store?.save()
        windows.close()
    }

    func installNow() {
        guard !isBusy, release != nil else { return }
        didChoose = true
        phase = .downloading
        downloadProgress = nil
        installTask = Task { await self.install() }
    }

    func noteWindowClosed() {
        installTask?.cancel()
        guard !didChoose else { return }
        didChoose = true
        saveRemind()
    }

    private func runCheck(store: AppPreferencesStore, now: Date, manual: Bool) async -> String {
        if let running {
            return await running.value
        }
        let task = Task { await self.fetchAndPresent(store: store, now: now, manual: manual) }
        running = task
        let status = await task.value
        running = nil
        return status
    }

    private func fetchAndPresent(store: AppPreferencesStore, now: Date, manual: Bool) async -> String {
        do {
            let latest = try await feed.latestRelease()
            remember(latest, store: store, now: now)
            return presentIfNeeded(latest, store: store, now: now, manual: manual)
        } catch {
            return manual ? String(localized: "Couldn't check for updates.") : ""
        }
    }

    private func presentIfNeeded(
        _ latest: AppRelease?,
        store: AppPreferencesStore,
        now: Date,
        manual: Bool
    ) -> String {
        guard let latest, AppUpdatePolicy.isNewer(latest.version, than: AppVersion.marketing) else {
            return manual ? String(localized: "Vermail is up to date.") : ""
        }
        let prompt = UpdatePrompt(now: now, current: AppVersion.marketing, release: latest, manual: manual)
        guard AppUpdatePolicy.shouldPrompt(store.preferences, prompt) else { return "" }
        present(latest)
        return ""
    }

    private func remember(_ latest: AppRelease?, store: AppPreferencesStore, now: Date) {
        var preferences = store.preferences
        preferences.lastUpdateCheckAt = now
        if let latest, AppUpdatePolicy.isNewer(latest.version, than: AppVersion.marketing) {
            if preferences.pendingUpdateVersion != latest.version {
                preferences.updateRemindAfter = nil
            }
            preferences.pendingUpdateVersion = latest.version
            preferences.pendingUpdateNotes = latest.notes
            preferences.pendingUpdateURL = latest.assetURL.absoluteString
        } else {
            preferences.pendingUpdateVersion = nil
            preferences.pendingUpdateNotes = nil
            preferences.pendingUpdateURL = nil
            preferences.updateRemindAfter = nil
        }
        store.preferences = preferences
        store.save()
    }

    private func present(_ release: AppRelease) {
        guard !isBusy else {
            windows.show(self)
            return
        }
        self.release = release
        phase = .ready
        didChoose = false
        windows.show(self)
    }

    private func install() async {
        guard let release else { return }
        do {
            phase = .downloading
            downloadProgress = nil
            try await UpdateLauncher.install(release) { [weak self] progress in
                guard let self else { return }
                Task { @MainActor in
                    self.downloadProgress = progress
                }
            }
            phase = .installing
            downloadProgress = nil
            quitSoTheUpdaterCanReplaceTheApp()
        } catch is CancellationError {
            phase = .ready
            downloadProgress = nil
            didChoose = false
        } catch {
            phase = .failed(error.localizedDescription)
            downloadProgress = nil
            didChoose = false
        }
    }

    private func quitSoTheUpdaterCanReplaceTheApp() {
        // terminate() closes the windows and leaves the process alive. macOS then reports
        // that Vermail is running in the background and does not bring the new copy forward.
        exit(0)
    }

    private func saveRemind() {
        guard var preferences = store?.preferences else { return }
        let delay = TimeInterval(AppUpdatePolicy.intervalDays(preferences)) * AppUpdatePolicy.day
        preferences.updateRemindAfter = Date().addingTimeInterval(delay)
        store?.preferences = preferences
        store?.save()
    }
}
