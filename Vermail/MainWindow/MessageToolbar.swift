import MailCore
import MailStorage
import SwiftUI

/// Message actions live in the window toolbar, above the open message.
struct MessageToolbar: ToolbarContent {
    @Bindable var viewModel: MainWindowViewModel
    /// When set, every action applies to this message instead of the list selection.
    var messageID: Int64?
    var onDelete: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if message?.folder == .drafts {
                actionButton("Edit Draft", systemImage: "square.and.pencil") {
                    compose(.editDraft)
                }
            }
            actionButton("Reply", systemImage: "arrowshape.turn.up.left") {
                compose(.reply)
            }
            actionButton("Reply All", systemImage: "arrowshape.turn.up.left.2") {
                compose(.replyAll)
            }
            actionButton("Forward", systemImage: "arrowshape.turn.up.right") {
                compose(.forward)
            }
            actionButton("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            actionButton("Archive", systemImage: "archivebox") {
                let ids = listActionIDs
                guard !ids.isEmpty else { return }
                Task { await viewModel.move(ids: ids, to: .archive) }
            }
            moveMenu
            actionButton(
                selectionIsRead ? "Mark as Unread" : "Mark as Read",
                systemImage: selectionIsRead ? "envelope.badge" : "envelope.open"
            ) {
                let ids = listActionIDs
                guard !ids.isEmpty else { return }
                Task { await viewModel.toggleRead(ids: ids) }
            }
        }
    }

    private var message: StoredMessage? {
        let id = messageID ?? viewModel.selectedMessageID
        return viewModel.messages.first { $0.id == id }
    }

    private var hasMessage: Bool {
        message != nil || !listActionIDs.isEmpty
    }

    private var listActionIDs: [Int64] {
        if let messageID {
            return [messageID]
        }
        return viewModel.idsForListActions()
    }

    private var selectionIsRead: Bool {
        let ids = Set(listActionIDs)
        return !viewModel.messages.contains { ids.contains($0.id) && !$0.isRead }
    }

    private func compose(_ request: ComposeRequest) {
        if let messageID {
            viewModel.openCompose(request, focusing: messageID)
        } else {
            viewModel.openCompose(request)
        }
    }

    private var moveMenu: some View {
        Menu {
            ForEach(MailFolderKind.allCases, id: \.self) { folder in
                if folder != .allMail {
                    Button {
                        let ids = listActionIDs
                        guard !ids.isEmpty else { return }
                        Task { await viewModel.move(ids: ids, to: folder) }
                    } label: {
                        Label {
                            Text(folder.title)
                        } icon: {
                            Image(systemName: folder.systemImage)
                        }
                    }
                }
            }
        } label: {
            Label("Move", systemImage: "folder")
        }
        .help("Move")
        .disabled(!hasMessage)
    }

    private func actionButton(
        _ title: LocalizedStringResource,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
            }
        }
        .help(Text(title))
        .disabled(!hasMessage)
        .labelStyle(.iconOnly)
    }
}
