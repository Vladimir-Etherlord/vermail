import AppKit
import Foundation
import UserNotifications

@MainActor
protocol DockBadgeUpdating: AnyObject {
    func updateBadge(to label: String?)
}

@MainActor
protocol MailAnnouncing: AnyObject {
    func authorizationGranted() async -> Bool
    func post(_ alerts: [MailAlert], playSound: Bool) async
}

@MainActor
protocol NewMailSoundPlaying: AnyObject {
    func play()
}

struct MenuBarSnapshot: Equatable, Sendable {
    var isVisible: Bool
    var unreadCount: Int
    var canCheck: Bool
}

@MainActor
protocol MenuBarControlling: AnyObject {
    func render(_ snapshot: MenuBarSnapshot, onCheck: @escaping () -> Void)
}

@MainActor
struct SystemServices {
    var dockBadge: any DockBadgeUpdating
    var announcer: any MailAnnouncing
    var sound: any NewMailSoundPlaying
    var menuBar: any MenuBarControlling
    var applicationIsActive: () -> Bool

    static var live: SystemServices {
        SystemServices(
            dockBadge: DockTileBadge(),
            announcer: SystemMailAnnouncer(),
            sound: SystemNewMailSound(),
            menuBar: StatusItemMenuBar(),
            applicationIsActive: { NSApp.isActive }
        )
    }

    static var quiet: SystemServices {
        SystemServices(
            dockBadge: IgnoredDockBadge(),
            announcer: SilentAnnouncer(),
            sound: SilentNewMailSound(),
            menuBar: HiddenMenuBar(),
            applicationIsActive: { false }
        )
    }
}

@MainActor
final class IgnoredDockBadge: DockBadgeUpdating {
    private(set) var label: String?

    func updateBadge(to label: String?) {
        self.label = label
    }
}

@MainActor
final class DockTileBadge: DockBadgeUpdating {
    func updateBadge(to label: String?) {
        NSApp.dockTile.badgeLabel = label
    }
}

@MainActor
final class HiddenMenuBar: MenuBarControlling {
    func render(_: MenuBarSnapshot, onCheck _: @escaping () -> Void) {}
}

@MainActor
final class SilentAnnouncer: MailAnnouncing {
    func authorizationGranted() async -> Bool {
        false
    }

    func post(_: [MailAlert], playSound _: Bool) async {}
}

@MainActor
final class SystemMailAnnouncer: MailAnnouncing {
    func authorizationGranted() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            let options: UNAuthorizationOptions = [.alert, .sound]
            return await (try? center.requestAuthorization(options: options)) ?? false
        default:
            return false
        }
    }

    func post(_ alerts: [MailAlert], playSound: Bool) async {
        let center = UNUserNotificationCenter.current()
        for (index, alert) in alerts.enumerated() {
            try? await center.add(request(for: alert, playSound: playSound && index == 0))
        }
    }

    private func request(for alert: MailAlert, playSound: Bool) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.subtitle = alert.subtitle ?? ""
        content.body = alert.body
        if playSound {
            content.sound = .default
        }
        return UNNotificationRequest(identifier: alert.identifier, content: content, trigger: nil)
    }
}

@MainActor
final class SilentNewMailSound: NewMailSoundPlaying {
    func play() {}
}

@MainActor
final class SystemNewMailSound: NewMailSoundPlaying {
    func play() {
        NSSound(named: NSSound.Name("Ping"))?.play()
    }
}

@MainActor
final class SleepWakeMonitor: NSObject {
    private let onWake: @MainActor () -> Void

    init(onWake: @escaping @MainActor () -> Void) {
        self.onWake = onWake
        super.init()
    }

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func handleWake() {
        onWake()
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
