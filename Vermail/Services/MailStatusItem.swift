import AppKit
import Foundation

enum MenuBarContent {
    static func buttonTitle(unreadCount: Int) -> String {
        unreadCount > 0 ? "\(min(unreadCount, 999))" : ""
    }

    static func statusTitle(unreadCount: Int) -> String {
        if unreadCount == 0 {
            return String(localized: "No Unread Messages")
        }
        return String(localized: "\(unreadCount) unread")
    }
}

@MainActor
final class StatusItemMenuBar: MenuBarControlling {
    private var item: NSStatusItem?
    private var commands: [MenuCommand] = []

    func render(_ snapshot: MenuBarSnapshot, onCheck: @escaping () -> Void) {
        guard snapshot.isVisible else {
            removeItem()
            return
        }
        let title = MenuBarContent.buttonTitle(unreadCount: snapshot.unreadCount)
        let item = item ?? NSStatusBar.system.statusItem(
            withLength: title.isEmpty ? NSStatusItem.squareLength : NSStatusItem.variableLength
        )
        self.item = item
        item.length = title.isEmpty ? NSStatusItem.squareLength : NSStatusItem.variableLength
        item.button?.image = ApplicationIcon.image(side: 18)
        item.button?.imageScaling = .scaleProportionallyDown
        item.button?.title = title
        item.menu = menu(for: snapshot, onCheck: onCheck)
    }

    private func menu(for snapshot: MenuBarSnapshot, onCheck: @escaping () -> Void) -> NSMenu {
        commands = []
        let menu = NSMenu()
        menu.addItem(disabledItem(MenuBarContent.statusTitle(unreadCount: snapshot.unreadCount)))
        menu.addItem(commandItem(String(localized: "Check Mail"), enabled: snapshot.canCheck, action: onCheck))
        menu.addItem(.separator())
        menu.addItem(commandItem(String(localized: "Open Vermail"), enabled: true) { [weak self] in
            self?.openMainWindow()
        })
        menu.addItem(commandItem(String(localized: "Settings…"), enabled: true) { [weak self] in
            self?.openSettings()
        })
        return menu
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func commandItem(_ title: String, enabled: Bool, action: @escaping () -> Void) -> NSMenuItem {
        let command = MenuCommand(action: action)
        commands.append(command)
        let item = NSMenuItem(title: title, action: #selector(MenuCommand.invoke), keyEquivalent: "")
        item.target = command
        item.isEnabled = enabled
        return item
    }

    private func removeItem() {
        guard let item else { return }
        NSStatusBar.system.removeStatusItem(item)
        self.item = nil
        commands = []
    }

    private func openMainWindow() {
        NSApp.activate()
        let hasVisibleMainWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
        if hasVisibleMainWindow {
            NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        } else {
            _ = NSApp.delegate?.applicationShouldHandleReopen?(NSApp, hasVisibleWindows: false)
        }
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

@MainActor
private final class MenuCommand: NSObject {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func invoke() {
        action()
    }
}
