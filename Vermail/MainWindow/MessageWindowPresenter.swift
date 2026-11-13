import AppKit
import MailStorage
import MIMEKit
import SwiftUI

@MainActor
final class MessageWindowPresenter {
    private final class CloseWatcher: NSObject, NSWindowDelegate {
        var onClose: () -> Void = {}

        func windowWillClose(_: Notification) {
            onClose()
        }
    }

    private var windows: [Int64: NSWindow] = [:]
    private var watchers: [Int64: CloseWatcher] = [:]

    func open(messageID: Int64, viewModel: MainWindowViewModel) {
        if let window = windows[messageID] {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 560, height: 420)
        window.title = Self.title(for: messageID, viewModel: viewModel)
        window.isReleasedWhenClosed = false

        let watcher = CloseWatcher()
        watcher.onClose = { [weak self] in
            Task { @MainActor in
                self?.windows[messageID] = nil
                self?.watchers[messageID] = nil
            }
        }
        window.delegate = watcher
        watchers[messageID] = watcher
        windows[messageID] = window

        let hosting = NSHostingController(
            rootView: MessageViewerRoot(messageID: messageID, viewModel: viewModel) {
                window.close()
            }
        )
        hosting.sizingOptions = []
        window.contentViewController = hosting
        if !WindowFrameStore.restore(window, name: "VermailMessage") {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private static func title(for messageID: Int64, viewModel: MainWindowViewModel) -> String {
        let raw = viewModel.messages.first { $0.id == messageID }?.subject ?? ""
        let decoded = MIME.decodedHeader(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        if decoded.isEmpty {
            return String(localized: "(No Subject)")
        }
        return decoded
    }
}

private struct MessageViewerRoot: View {
    let messageID: Int64
    @Bindable var viewModel: MainWindowViewModel
    var onClose: () -> Void

    @State private var parsed: MIMEMessage?
    @State private var confirmDelete = false

    var body: some View {
        viewer
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                MessageToolbar(viewModel: viewModel, messageID: messageID) {
                    requestDelete()
                }
            }
            .background(WindowFrameAutosave(name: "VermailMessage", iconOnlyToolbar: true))
            .task(id: messageID) {
                parsed = await viewModel.parsedMessage(id: messageID)
            }
            .onChange(of: listedMessageIDs) { _, ids in
                if !ids.contains(messageID) {
                    onClose()
                }
            }
            .alert("Delete Messages?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) {
                    Task { await viewModel.delete(ids: [messageID]) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This moves the selected messages to the Trash. Messages already in the Trash are deleted.")
            }
    }

    @ViewBuilder
    private var viewer: some View {
        if let message {
            MessageDetailView(
                message: message,
                parsedMessage: parsed,
                currentFolder: message.folder,
                shouldShowRemoteImageBanner: viewModel.shouldShowRemoteImageBanner(
                    for: message,
                    html: parsed?.htmlBody
                ),
                allowRemoteImages: viewModel.allowsRemoteImages(for: message),
                onAllowImagesOnce: { viewModel.allowRemoteImagesOnce(messageID: message.id) },
                onAllowImagesAlways: { viewModel.allowRemoteImagesAlways(sender: message.fromAddress) }
            )
        } else {
            ContentUnavailableView("No Message Selected", systemImage: "envelope")
        }
    }

    private var message: StoredMessage? {
        viewModel.messages.first { $0.id == messageID }
    }

    private var listedMessageIDs: [Int64] {
        viewModel.messages.map(\.id)
    }

    private func requestDelete() {
        if viewModel.preferencesStore.preferences.confirmDelete {
            confirmDelete = true
        } else {
            Task { await viewModel.delete(ids: [messageID]) }
        }
    }
}
