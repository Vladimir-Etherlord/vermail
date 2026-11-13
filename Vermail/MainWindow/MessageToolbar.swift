import MailCore
import SwiftUI

/// Message actions live in the window toolbar, above the open message.
struct MessageToolbar: ToolbarContent {
    @Bindable var viewModel: MainWindowViewModel
    var onDelete: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if viewModel.selectedMessage?.folder == .drafts {
                actionButton("Edit Draft", systemImage: "square.and.pencil") {
                    viewModel.openCompose(.editDraft)
                }
            }
            actionButton("Reply", systemImage: "arrowshape.turn.up.left") {
                viewModel.openCompose(.reply)
            }
            actionButton("Reply All", systemImage: "arrowshape.turn.up.left.2") {
                viewModel.openCompose(.replyAll)
            }
            actionButton("Forward", systemImage: "arrowshape.turn.up.right") {
                viewModel.openCompose(.forward)
            }
            actionButton("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            actionButton("Archive", systemImage: "archivebox") {
                guard let id = viewModel.selectedMessageID else { return }
                Task { await viewModel.move(ids: [id], to: .archive) }
            }
            moveMenu
            actionButton(
                viewModel.selectedMessage?.isRead == true ? "Mark as Unread" : "Mark as Read",
                systemImage: viewModel.selectedMessage?.isRead == true ? "envelope.badge" : "envelope.open"
            ) {
                guard let id = viewModel.selectedMessageID else { return }
                Task { await viewModel.toggleRead(ids: [id]) }
            }
        }
    }

    private var hasMessage: Bool {
        viewModel.selectedMessage != nil
    }

    private var moveMenu: some View {
        Menu {
            ForEach(MailFolderKind.allCases, id: \.self) { folder in
                if folder != .allMail {
                    Button {
                        guard let id = viewModel.selectedMessageID else { return }
                        Task { await viewModel.move(ids: [id], to: folder) }
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
