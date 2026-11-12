import Foundation
import MailCore

extension MainWindowViewModel {
    var inboxUnreadCount: Int {
        DockBadgeText.inboxUnreadCount(in: unreadCounts, accounts: accounts)
    }

    func startSystemServices() {
        applyDockBadge()
        guard checkLoop == nil else { return }
        let monitor = SleepWakeMonitor { [weak self] in
            Task { await self?.checkDueAccounts(forceAll: true) }
        }
        monitor.start()
        wakeMonitor = monitor
        checkLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkDueAccounts(forceAll: false)
                try? await Task.sleep(for: .seconds(30))
            }
        }
        requestNotificationAuthorizationIfNeeded()
    }

    func requestNotificationAuthorizationIfNeeded() {
        guard preferencesStore.preferences.notificationsEnabled else { return }
        Task { _ = await systemServices.announcer.authorizationGranted() }
    }

    func checkDueAccounts(forceAll: Bool, now: Date = .now) async {
        if forceAll {
            wantsFullCheck = true
        }
        guard !isSyncing else { return }
        let includeAll = wantsFullCheck
        wantsFullCheck = false
        let due = MailCheckPlanner.dueAccounts(
            among: accounts,
            lastCheckedAt: lastCheckedAt,
            now: now,
            includesAllEnabled: includeAll
        )
        await sync(due, now: now)
    }

    func refresh() async {
        await sync(accounts, now: .now)
    }

    func refresh(accountID: UUID) async {
        guard let account = accounts.first(where: { $0.id == accountID }) else { return }
        await sync([account], now: .now)
    }

    func applyDockBadge() {
        let label = DockBadgeText.label(
            unreadCount: inboxUnreadCount,
            isVisible: preferencesStore.preferences.showDockBadge
        )
        systemServices.dockBadge.updateBadge(to: label)
        systemServices.menuBar.render(
            MenuBarSnapshot(
                isVisible: preferencesStore.preferences.showMenuBarIcon,
                unreadCount: inboxUnreadCount,
                canCheck: !isSyncing && !accounts.isEmpty
            ),
            onCheck: { [weak self] in
                Task { await self?.refresh() }
            }
        )
    }

    private func sync(_ targets: [MailAccount], now: Date) async {
        let enabled = targets.filter(\.isEnabled)
        guard !enabled.isEmpty else { return }
        guard !isSyncing else {
            wantsFullCheck = true
            return
        }

        isSyncing = true
        applyDockBadge()
        for account in enabled {
            syncStates[account.id] = .syncing
        }
        let report = await syncEngine.syncAccounts(enabled)
        for (id, state) in report.states {
            syncStates[id] = state
            lastCheckedAt[id] = now
        }
        isSyncing = false
        await reloadMessages()
        await announce(report.newMail)
        if wantsFullCheck {
            await checkDueAccounts(forceAll: true, now: now)
        }
    }

    private func announce(_ notices: [IncomingMailNotice]) async {
        let alerts = MailAlertPlanner.makeAlerts(from: notices, accountNames: accountNames)
        guard !alerts.isEmpty else { return }
        let preferences = preferencesStore.preferences
        if preferences.playSounds, systemServices.applicationIsActive() {
            systemServices.sound.play()
        }
        guard preferences.notificationsEnabled, await systemServices.announcer.authorizationGranted() else { return }
        let playSound = preferences.playSounds && !systemServices.applicationIsActive()
        await systemServices.announcer.post(alerts, playSound: playSound)
    }

    private var accountNames: [UUID: String] {
        Dictionary(uniqueKeysWithValues: accounts.map { account in
            let trimmed = account.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            return (account.id, trimmed.isEmpty ? account.emailAddress : trimmed)
        })
    }
}
