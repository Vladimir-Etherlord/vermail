import AppKit
import SwiftUI

@MainActor
final class AboutWindowPresenter {
    static let shared = AboutWindowPresenter()

    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 280),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "About Vermail")
        window.minSize = NSSize(width: 280, height: 240)
        window.isReleasedWhenClosed = false
        let hosting = NSHostingController(rootView: AboutView())
        hosting.sizingOptions = []
        window.contentViewController = hosting
        if !WindowFrameStore.restore(window, name: "VermailAbout") {
            window.center()
        }
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

private struct AboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: ApplicationIcon.image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 160, maxHeight: 160)
            Text("Vermail")
                .font(.title.bold())
            Text("Version \(AppVersion.marketing) (\(AppVersion.build))")
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WindowResizeEnabler(minSize: CGSize(width: 280, height: 240)))
    }
}
