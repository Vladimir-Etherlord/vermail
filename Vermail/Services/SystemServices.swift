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

enum DockBadgeAuthorization {
    static func needsRequest(status: UNAuthorizationStatus, badge: UNNotificationSetting) -> Bool {
        switch status {
        case .denied:
            false
        case .authorized, .provisional, .ephemeral:
            badge != .enabled
        case .notDetermined:
            true
        @unknown default:
            true
        }
    }
}

@MainActor
final class DockTileBadge: DockBadgeUpdating {
    func updateBadge(to label: String?) {
        let options: UNAuthorizationOptions = [.alert, .sound, .badge]
        UNUserNotificationCenter.current().requestAuthorization(options: options) { _, _ in }
        let tile = NSApp.dockTile
        tile.badgeLabel = nil
        if let label, !label.isEmpty {
            tile.contentView = DockIconBadgeView(label: label, size: tile.size)
        } else {
            tile.contentView = nil
        }
        tile.display()
    }
}

@MainActor
private final class DockIconBadgeView: NSView {
    private let label: String?

    init(label: String?, size: NSSize) {
        self.label = label
        super.init(frame: NSRect(origin: .zero, size: size))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func draw(_: NSRect) {
        Self.icon().draw(in: bounds)
        guard let label, !label.isEmpty else { return }
        let badge = Self.badgeRect(for: label, in: bounds)
        Self.drawBadge(label, in: badge)
    }

    private static func icon() -> NSImage {
        NSApp.applicationIconImage ?? NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }

    private static func badgeRect(for label: String, in bounds: NSRect) -> NSRect {
        let height = bounds.height * 0.42
        let font = NSFont.systemFont(ofSize: height * 0.56, weight: .bold)
        let textWidth = (label as NSString).size(withAttributes: [.font: font]).width
        let width = max(height, textWidth + height * 0.5)
        return NSRect(
            x: bounds.maxX - width - bounds.width * 0.03,
            y: bounds.maxY - height - bounds.height * 0.03,
            width: width,
            height: height
        )
    }

    private static func drawBadge(_ label: String, in rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = rect.height * 0.1
        shadow.set()
        NSColor.systemRed.setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
        NSGraphicsContext.restoreGraphicsState()
        let font = NSFont.systemFont(ofSize: rect.height * 0.56, weight: .bold)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let text = NSAttributedString(string: label, attributes: [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: style,
        ])
        let textSize = text.size()
        text.draw(in: NSRect(
            x: rect.minX,
            y: rect.midY - textSize.height / 2,
            width: rect.width,
            height: textSize.height
        ))
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
            let options: UNAuthorizationOptions = [.alert, .sound, .badge]
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
