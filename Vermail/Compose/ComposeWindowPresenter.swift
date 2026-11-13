import AppKit
import SwiftUI

@MainActor
final class ComposeWindowPresenter {
    private final class CloseWatcher: NSObject, NSWindowDelegate {
        var onClose: () -> Void = {}

        func windowWillClose(_: Notification) {
            onClose()
        }
    }

    private var watchers: [ObjectIdentifier: CloseWatcher] = [:]

    func open(
        model: ComposeViewModel,
        preferences: AppPreferencesStore,
        onFinish: @escaping () -> Void
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 640, height: 420)
        window.title = Self.title(for: model)
        window.isReleasedWhenClosed = false

        let watcher = CloseWatcher()
        let finish = FinishOnce(action: onFinish)
        watcher.onClose = { [weak self, weak window] in
            Task { @MainActor in
                if let window {
                    self?.watchers.removeValue(forKey: ObjectIdentifier(window))
                }
                finish.run()
            }
        }
        window.delegate = watcher
        watchers[ObjectIdentifier(window)] = watcher

        let hosting = NSHostingController(
            rootView: ComposeWindowRoot(model: model, preferences: preferences) {
                finish.run()
                window.close()
            }
        )
        hosting.sizingOptions = []
        window.contentViewController = hosting
        if !WindowFrameStore.restore(window, name: "VermailCompose") {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private static func title(for model: ComposeViewModel) -> String {
        let subject = model.draft.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if subject.isEmpty {
            return String(localized: "New Message")
        }
        return subject
    }
}

private final class FinishOnce {
    private var didFinish = false
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @MainActor
    func run() {
        guard !didFinish else { return }
        didFinish = true
        action()
    }
}

private struct ComposeWindowRoot: View {
    @Bindable var model: ComposeViewModel
    var preferences: AppPreferencesStore
    var onClose: () -> Void

    var body: some View {
        ComposeView(model: model, onClose: onClose)
            .environment(preferences)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
