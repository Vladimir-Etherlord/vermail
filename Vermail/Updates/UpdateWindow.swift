import AppKit
import SwiftUI

@MainActor
final class UpdateWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private weak var owner: AppUpdateController?

    func show(_ owner: AppUpdateController) {
        self.owner = owner
        let window = window ?? makeWindow(owner)
        self.window = window
        UpdateReplacer.placeInCenter(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        DispatchQueue.main.async {
            UpdateReplacer.placeInCenter(window)
        }
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_: Notification) {
        owner?.noteWindowClosed()
    }

    private func makeWindow(_ owner: AppUpdateController) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Software Update")
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        let hosting = NSHostingController(rootView: UpdateAvailableView(controller: owner))
        hosting.sizingOptions = []
        window.contentViewController = hosting
        return window
    }
}

struct UpdateAvailableView: View {
    @Bindable var controller: AppUpdateController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if controller.isBusy {
                busyState
            } else {
                header
                notes
                if let message = controller.failureMessage {
                    Text(verbatim: message)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                buttons
            }
        }
        .padding(20)
        .frame(width: 460, height: 280)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: ApplicationIcon.image)
                .resizable()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 6) {
                Text("A new version of Vermail is available")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                if let release = controller.release {
                    Text("Version \(release.version) is ready to install. This copy is \(AppVersion.marketing).")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var notes: some View {
        if let notes = controller.release?.notes, !notes.isEmpty {
            Text("What's New")
                .font(.headline)
            ScrollView {
                Text(verbatim: notes)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 140)
        }
    }

    private var buttons: some View {
        HStack {
            Spacer()
            Button("Skip This Version", action: controller.skipThisVersion)
            Button("Remind Me Later", action: controller.remindLater)
            Button("Update Now", action: controller.installNow)
                .keyboardShortcut(.defaultAction)
        }
        .disabled(controller.isBusy)
    }

    private var busyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Text(controller.statusLine)
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            if let progress = controller.downloadProgress {
                ProgressView(value: progress, total: 1)
                    .progressViewStyle(.linear)
                    .frame(width: 320)
                Text(progress.formatted(.percent.precision(.fractionLength(0))))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.regular)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
