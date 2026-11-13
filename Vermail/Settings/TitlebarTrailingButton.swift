import AppKit
import SwiftUI

/// A symbol button on the trailing edge of the window toolbar, level with the sidebar toggle.
struct TitlebarTrailingButton: NSViewRepresentable {
    var help: LocalizedStringResource
    var systemImage: String
    var action: () -> Void

    func makeNSView(context _: Context) -> TitlebarTrailingHost {
        TitlebarTrailingHost()
    }

    func updateNSView(_ host: TitlebarTrailingHost, context _: Context) {
        host.help = help
        host.systemImage = systemImage
        host.action = action
        host.installIfNeeded()
    }
}

final class TitlebarTrailingHost: NSView {
    var help: LocalizedStringResource = ""
    var systemImage = "plus"
    var action: () -> Void = {}

    private var button: NSButton?
    private weak var installedWindow: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        MainActor.assumeIsolated {
            if window == nil {
                removeButton()
            } else {
                installIfNeeded()
            }
        }
    }

    override func layout() {
        super.layout()
        MainActor.assumeIsolated { positionButton() }
    }

    @MainActor
    func installIfNeeded() {
        guard let window else { return }
        if button == nil {
            let button = NSButton()
            button.target = self
            button.action = #selector(handleClick)
            button.imagePosition = .imageOnly
            button.bezelStyle = .circular
            button.setButtonType(.momentaryPushIn)
            button.controlSize = .large
            button.keyEquivalent = ""
            self.button = button
            installedWindow = window
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowFrameChanged),
                name: NSWindow.didResizeNotification,
                object: window
            )
        }
        refreshButton()
        positionButton()
    }

    @MainActor
    private func refreshButton() {
        guard let button else { return }
        let title = String(localized: help)
        button.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        button.toolTip = title
        button.setAccessibilityLabel(title)
    }

    @MainActor
    private func positionButton() {
        guard let button, let window, let container = toolbarContainer(in: window) else { return }
        if button.superview !== container {
            container.addSubview(button)
        }
        let side: CGFloat = 28
        let toggleFrame = sidebarToggleFrame(in: window, container: container)
        let originY = toggleFrame.height > 0 ? toggleFrame.midY - side / 2 : (container.bounds.height - side) / 2
        let next = NSRect(x: container.bounds.width - side - 14, y: originY, width: side, height: side)
        if button.frame.integral != next.integral {
            button.frame = next
        }
    }

    @MainActor
    private func toolbarContainer(in window: NSWindow) -> NSView? {
        guard let toggle = sidebarToggle(in: window) else { return nil }
        let targetWidth = window.frame.width
        var view: NSView? = toggle.superview
        while let current = view, current.bounds.width < targetWidth - 80 {
            view = current.superview
        }
        return view
    }

    @MainActor
    private func sidebarToggle(in window: NSWindow) -> NSView? {
        window.toolbar?.items.first {
            $0.itemIdentifier.rawValue.contains("toggleSidebar")
        }?.view
    }

    @MainActor
    private func sidebarToggleFrame(in window: NSWindow, container: NSView) -> NSRect {
        guard let toggle = sidebarToggle(in: window) else { return .zero }
        return toggle.convert(toggle.bounds, to: container)
    }

    @MainActor
    private func removeButton() {
        if let installedWindow {
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didResizeNotification,
                object: installedWindow
            )
        }
        button?.target = nil
        button?.removeFromSuperview()
        button = nil
        installedWindow = nil
    }

    @objc private func handleClick() {
        MainActor.assumeIsolated { action() }
    }

    @objc private func windowFrameChanged() {
        MainActor.assumeIsolated { positionButton() }
    }
}
