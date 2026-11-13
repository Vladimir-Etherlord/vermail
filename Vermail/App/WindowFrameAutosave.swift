import AppKit
import SwiftUI

@MainActor
enum WindowFrameStore {
    /// Restores a previously saved frame, then keeps saving this window's frame.
    @discardableResult
    static func restore(_ window: NSWindow, name: String) -> Bool {
        let restored = window.setFrameUsingName(name)
        window.setFrameAutosaveName(name)
        return restored
    }
}

/// Remembers a SwiftUI window's size and position. The restore waits until SwiftUI
/// has applied its default size, otherwise that default overwrites the saved frame.
struct WindowFrameAutosave: NSViewRepresentable {
    var name: String
    var iconOnlyToolbar = false

    func makeNSView(context _: Context) -> NSView {
        let view = FrameAutosaveView()
        view.autosaveName = name
        view.iconOnlyToolbar = iconOnlyToolbar
        return view
    }

    func updateNSView(_ view: NSView, context _: Context) {
        guard let view = view as? FrameAutosaveView else { return }
        view.autosaveName = name
        view.iconOnlyToolbar = iconOnlyToolbar
        view.scheduleRestore()
    }
}

private final class FrameAutosaveView: NSView {
    var autosaveName = ""
    var iconOnlyToolbar = false
    private var scheduled = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        MainActor.assumeIsolated {
            scheduled = false
            scheduleRestore()
        }
    }

    @MainActor
    func scheduleRestore() {
        guard window != nil, !scheduled, !autosaveName.isEmpty else { return }
        scheduled = true
        let name = autosaveName
        let iconOnly = iconOnlyToolbar
        // SwiftUI applies `.defaultSize` during the next layout. Restore after that, then start saving.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.applySavedFrame(name)
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated {
                        guard let window = self?.window else { return }
                        WindowFrameStore.restore(window, name: name)
                        if iconOnly {
                            window.toolbar?.displayMode = .iconOnly
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private func applySavedFrame(_ name: String) {
        guard let window else { return }
        _ = window.setFrameUsingName(name)
    }
}
