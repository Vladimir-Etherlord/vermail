import AppKit
import Foundation
import MailCore
import MailStorage
import Testing
@testable import Vermail

@MainActor
struct SystemIntegrationTests {
    @Test func checkScheduleHonorsIntervalAndWake() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let recent = account(name: "Recent", minutes: 10)
        let due = account(name: "Due", minutes: 5)
        let disabled = account(name: "Off", minutes: 1, enabled: false)
        let lastChecked = [
            recent.id: now.addingTimeInterval(-9 * 60),
            due.id: now.addingTimeInterval(-5 * 60),
            disabled.id: now.addingTimeInterval(-10 * 60),
        ]

        let scheduled = MailCheckPlanner.dueAccounts(
            among: [recent, due, disabled],
            lastCheckedAt: lastChecked,
            now: now,
            includesAllEnabled: false
        )
        #expect(scheduled.map(\.id) == [due.id])

        let forced = MailCheckPlanner.dueAccounts(
            among: [recent, due, disabled],
            lastCheckedAt: lastChecked,
            now: now,
            includesAllEnabled: true
        )
        #expect(forced.map(\.id) == [recent.id, due.id])

        let neverChecked = MailCheckPlanner.dueAccounts(
            among: [recent],
            lastCheckedAt: [:],
            now: now,
            includesAllEnabled: false
        )
        #expect(neverChecked.map(\.id) == [recent.id])
    }

    @Test func dockBadgeUsesEnabledInboxCounts() {
        let work = account(name: "Work", minutes: 5)
        let paused = account(name: "Paused", minutes: 5, enabled: false)
        let counts = UnreadCounts(byAccount: [
            work.id: [.inbox: 2, .trash: 9],
            paused.id: [.inbox: 4],
        ])

        #expect(DockBadgeText.inboxUnreadCount(in: counts, accounts: [work, paused]) == 2)
        #expect(DockBadgeText.label(unreadCount: 2, isVisible: true) == "2")
        #expect(DockBadgeText.label(unreadCount: 2, isVisible: false) == nil)
        #expect(DockBadgeText.label(unreadCount: 0, isVisible: true) == nil)
        #expect(DockBadgeText.label(unreadCount: 1500, isVisible: true) == "999+")
        #expect(MenuBarContent.buttonTitle(unreadCount: 0).isEmpty)
        #expect(MenuBarContent.buttonTitle(unreadCount: 3) == "3")
        #expect(MenuBarContent.buttonTitle(unreadCount: 1500) == "999")
        #expect(MenuBarContent.statusTitle(unreadCount: 0) == String(localized: "No Unread Messages"))
        #expect(MenuBarContent.statusTitle(unreadCount: 3) == String(localized: "\(3) unread"))
    }

    @Test func alertsDescribeNewMailAndCollapseABurst() {
        let work = UUID()
        let home = UUID()
        let hello = notice(account: work, uid: "a", from: "\"Ada\" <ada@example.com>", subject: "Hello")
        let one = MailAlertPlanner.makeAlerts(from: [hello], accountNames: [work: "Work"])
        #expect(one.map(\.title) == ["Ada"])
        #expect(one.map(\.body) == ["Hello"])
        #expect(one.map(\.subtitle) == [nil])

        let named = MailAlertPlanner.makeAlerts(
            from: [hello],
            accountNames: [work: "Work", home: "Home"]
        )
        #expect(named.map(\.subtitle) == ["Work"])

        let silent = notice(account: work, uid: "old", from: "Ada <ada@example.com>", subject: "Old", announces: false)
        #expect(MailAlertPlanner.makeAlerts(from: [silent], accountNames: [:]).isEmpty)

        let burst = (1 ... 4).map { index in
            notice(account: work, uid: "uid-\(index)", from: "Bob <bob@example.com>", subject: "Subject \(index)")
        }
        let summary = MailAlertPlanner.makeAlerts(from: burst, accountNames: [work: "Work"])
        #expect(summary.count == 1)
        #expect(summary[0].identifier == "mail-summary-4-uid-1")
        #expect(summary[0].body == "Bob: Subject 1")

        let blank = notice(account: work, uid: "blank", from: nil, subject: " ")
        let fallback = MailAlertPlanner.makeAlerts(from: [blank], accountNames: [work: "Work"])
        #expect(fallback[0].title == String(localized: "New Message"))
        #expect(fallback[0].body == String(localized: "(No Subject)"))
    }

    @Test func wakeNotificationInvokesTheHandler() {
        var hits = 0
        let monitor = SleepWakeMonitor { hits += 1 }
        monitor.start()
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(hits == 1)
    }

    @Test func scheduledCheckNotifiesOnceAndSkipsUntilTheNextInterval() async throws {
        let harness = try await Harness.make()
        defer { harness.cleanup() }
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        await harness.viewModel.loadInitialData()
        #expect(harness.badge.label == "1")
        #expect(harness.menuBar.snapshot == MenuBarSnapshot(isVisible: true, unreadCount: 1, canCheck: true))

        await harness.viewModel.checkDueAccounts(forceAll: false, now: now)
        #expect(await harness.fetcher.listCount == 1)
        #expect(harness.announcer.alerts.map(\.title) == ["Ada"])
        #expect(harness.announcer.playedNotificationSound)
        #expect(harness.sound.playCount == 0)
        #expect(harness.badge.label == "2")

        await harness.viewModel.checkDueAccounts(forceAll: false, now: now.addingTimeInterval(30))
        #expect(await harness.fetcher.listCount == 1)

        await harness.viewModel.checkDueAccounts(forceAll: true, now: now.addingTimeInterval(30))
        #expect(await harness.fetcher.listCount == 2)
        #expect(harness.announcer.alerts.count == 1)
    }

    private func account(name: String, minutes: Int, enabled: Bool = true) -> MailAccount {
        MailAccount(
            displayName: name,
            emailAddress: "\(name.lowercased())@example.com",
            incomingProtocol: .pop3,
            isEnabled: enabled,
            details: AccountDetails(checkIntervalMinutes: minutes)
        )
    }

    private func notice(
        account: UUID,
        uid: String,
        from: String?,
        subject: String,
        announces: Bool = true
    ) -> IncomingMailNotice {
        IncomingMailNotice(
            accountID: account,
            remoteUID: uid,
            fromAddress: from,
            subject: subject,
            snippet: nil,
            announcesArrival: announces
        )
    }
}

@MainActor
private final class RecordingAnnouncer: MailAnnouncing {
    var alerts: [MailAlert] = []
    var playedNotificationSound = false

    func authorizationGranted() async -> Bool {
        true
    }

    func post(_ alerts: [MailAlert], playSound: Bool) async {
        self.alerts.append(contentsOf: alerts)
        playedNotificationSound = playSound
    }
}

@MainActor
private final class RecordingMenuBar: MenuBarControlling {
    var snapshot: MenuBarSnapshot?

    func render(_ snapshot: MenuBarSnapshot, onCheck _: @escaping () -> Void) {
        self.snapshot = snapshot
    }
}

@MainActor
private final class RecordingSound: NewMailSoundPlaying {
    var playCount = 0
    func play() {
        playCount += 1
    }
}

@MainActor
private struct Harness {
    let viewModel: MainWindowViewModel
    let fetcher: CountingFetcher
    let announcer: RecordingAnnouncer
    let sound: RecordingSound
    let badge: IgnoredDockBadge
    let menuBar: RecordingMenuBar
    let cleanup: () -> Void

    static func make() async throws -> Harness {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SystemIntegration-\(UUID().uuidString)", directoryHint: .isDirectory)
        let database = try MailDatabase(rootDirectory: root)
        let account = workAccount()
        let accountStore = AccountStore(fileURL: root.appending(path: "accounts.json"))
        try accountStore.saveAccounts([account])
        try await seedKnownMessage(in: database, accountID: account.id)
        let fetcher = CountingFetcher.freshMail()
        let engine = MailSyncEngine(
            database: database,
            secretStore: InMemorySecretStore(),
            fetcherFactory: SingleFetcherFactory(fetcher: fetcher)
        )
        return try assemble(
            root: root,
            database: database,
            accountStore: accountStore,
            engine: engine,
            fetcher: fetcher
        )
    }

    private static func workAccount() -> MailAccount {
        MailAccount(
            displayName: "Work",
            emailAddress: "user@example.com",
            incomingProtocol: .pop3,
            details: AccountDetails(checkIntervalMinutes: 5)
        )
    }

    private static func assemble(
        root: URL,
        database: MailDatabase,
        accountStore: AccountStore,
        engine: MailSyncEngine,
        fetcher: CountingFetcher
    ) throws -> Harness {
        let suiteName = "SystemIntegration.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let preferences = AppPreferencesStore(defaults: defaults)
        let announcer = RecordingAnnouncer()
        let sound = RecordingSound()
        let badge = IgnoredDockBadge()
        let menuBar = RecordingMenuBar()
        let viewModel = MainWindowViewModel(
            database: database,
            accountStore: accountStore,
            syncEngine: engine,
            preferencesStore: preferences,
            systemServices: SystemServices(
                dockBadge: badge,
                announcer: announcer,
                sound: sound,
                menuBar: menuBar,
                applicationIsActive: { false }
            )
        )
        return Harness(
            viewModel: viewModel,
            fetcher: fetcher,
            announcer: announcer,
            sound: sound,
            badge: badge,
            menuBar: menuBar,
            cleanup: {
                defaults.removePersistentDomain(forName: suiteName)
                try? FileManager.default.removeItem(at: root)
            }
        )
    }

    private static func seedKnownMessage(in database: MailDatabase, accountID: UUID) async throws {
        _ = try await database.upsertMessage(StoredMessageInput(
            accountID: accountID,
            remoteUID: "known",
            folder: .inbox,
            subject: "Already here",
            fromAddress: "old@example.com",
            toAddresses: ["user@example.com"],
            snippet: "Old",
            receivedAt: Date(),
            rawSource: Data("Subject: Already here\r\n\r\nOld".utf8)
        ))
    }
}

private struct SingleFetcherFactory: MailFetcherFactory {
    let fetcher: CountingFetcher

    func makeFetcher(
        for _: MailAccount,
        secretStore _: any AccountSecretStore
    ) async throws -> (fetcher: any MailFetching, cleanup: @Sendable () async -> Void) {
        (fetcher, {})
    }
}

private actor CountingFetcher: MailFetching {
    let refs: [RemoteMessageRef]
    let payloads: [String: Data]
    private(set) var listCount = 0

    init(refs: [RemoteMessageRef], payloads: [String: Data]) {
        self.refs = refs
        self.payloads = payloads
    }

    static func freshMail() -> CountingFetcher {
        CountingFetcher(
            refs: [
                RemoteMessageRef(uid: "known", size: 10),
                RemoteMessageRef(uid: "fresh", size: 20),
            ],
            payloads: ["fresh": Data("From: Ada <ada@example.com>\r\nSubject: Fresh\r\n\r\nHello".utf8)]
        )
    }

    func listMessages() async throws -> [RemoteMessageRef] {
        listCount += 1
        return refs
    }

    func fetchMessage(_ ref: RemoteMessageRef) async throws -> Data {
        payloads[ref.uid] ?? Data()
    }

    func deleteMessages(_: [RemoteMessageRef]) async throws {}
}
