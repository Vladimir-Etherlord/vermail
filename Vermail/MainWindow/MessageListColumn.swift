import MailCore
import MailStorage
import SwiftUI

/// Folder title, New Message, and the unread filter share the list column's toolbar.
struct MessageListColumn: View {
    @Bindable var viewModel: MainWindowViewModel
    var requestDelete: ([Int64]) -> Void

    var body: some View {
        messageList
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .searchable(text: searchBinding, placement: .toolbar)
            .toolbar { mailboxToolbar }
    }

    @ToolbarContentBuilder
    private var mailboxToolbar: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.flexible, placement: .primaryAction)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button("New Message", systemImage: "square.and.pencil") {
                viewModel.openCompose(.newMessage)
            }
            .labelStyle(.iconOnly)
            .help("New Message")
            .disabled(viewModel.accounts.filter(\.isEnabled).isEmpty)

            Toggle(isOn: Binding(
                get: { viewModel.showUnreadOnly },
                set: { value in Task { await viewModel.setShowUnreadOnly(value) } }
            )) {
                Label(
                    "Unread Only",
                    systemImage: viewModel.showUnreadOnly
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle"
                )
            }
            .toggleStyle(.button)
            .labelStyle(.iconOnly)
            .help("Show Unread Messages Only")
        }
    }

    private var searchBinding: Binding<String> {
        Binding(
            get: { viewModel.searchQuery },
            set: { viewModel.updateSearchQuery($0) }
        )
    }

    private var messageSelectionBinding: Binding<Set<Int64>> {
        Binding(
            get: { viewModel.selectedMessageIDs },
            set: { viewModel.applyMessageSelection($0) }
        )
    }

    @ViewBuilder
    private var messageList: some View {
        if viewModel.messages.isEmpty {
            if !viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView.search(text: viewModel.searchQuery)
            } else {
                ContentUnavailableView("No Messages", systemImage: "tray")
            }
        } else {
            List(viewModel.messages, selection: messageSelectionBinding) { message in
                MessageRowView(
                    message: message,
                    accountColor: accountMarkerColor(for: message.accountID),
                    showAvatar: viewModel.preferencesStore.preferences.showAvatars,
                    showPreview: viewModel.preferencesStore.preferences.showMessagePreview
                )
                .tag(message.id)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        Task { await viewModel.toggleRead(ids: [message.id]) }
                    } label: {
                        Label(
                            message.isRead ? "Mark as Unread" : "Mark as Read",
                            systemImage: message.isRead ? "envelope.badge" : "envelope.open"
                        )
                    }
                    .tint(.blue)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        requestDelete([message.id])
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    Button {
                        Task { await viewModel.move(ids: [message.id], to: .archive) }
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    .tint(.indigo)
                }
            }
            .contextMenu(forSelectionType: Int64.self) { ids in
                MessageSelectionMenu(viewModel: viewModel, ids: ids, requestDelete: requestDelete)
            } primaryAction: { ids in
                if let id = viewModel.focusedMessageID(in: ids) {
                    viewModel.openMessageWindow(id)
                }
            }
            .onDeleteCommand {
                requestDelete(viewModel.idsForListActions())
            }
        }
    }

    private func accountMarkerColor(for accountID: UUID) -> Color? {
        guard case .unified = viewModel.selectedMailbox.scope, viewModel.accounts.count > 1,
              let account = viewModel.accounts.first(where: { $0.id == accountID })
        else {
            return nil
        }
        return AccountAppearance.color(named: account.details?.colorName)
    }
}

private struct MessageSelectionMenu: View {
    @Bindable var viewModel: MainWindowViewModel
    var ids: Set<Int64>
    var requestDelete: ([Int64]) -> Void

    var body: some View {
        Button(anyUnread ? "Mark as Read" : "Mark as Unread") {
            Task { await viewModel.toggleRead(ids: orderedIDs) }
        }
        if let draft = singleDraft {
            Button("Edit Draft") {
                Task {
                    await viewModel.selectMessage(draft.id)
                    viewModel.openCompose(.editDraft)
                }
            }
        }
        replyButtons
        Button("Archive") {
            Task { await viewModel.move(ids: orderedIDs, to: .archive) }
        }
        moveMenu
        Divider()
        Button("Delete", role: .destructive) {
            requestDelete(orderedIDs)
        }
    }

    @ViewBuilder
    private var replyButtons: some View {
        if let replyID {
            Button("Reply") {
                compose(.reply, id: replyID)
            }
            Button("Reply All") {
                compose(.replyAll, id: replyID)
            }
            Button("Forward") {
                compose(.forward, id: replyID)
            }
        }
    }

    private var moveMenu: some View {
        Menu("Move to Folder") {
            ForEach(MailFolderKind.allCases, id: \.self) { folder in
                if folder != .allMail {
                    Button {
                        Task { await viewModel.move(ids: orderedIDs, to: folder) }
                    } label: {
                        Text(folder.title)
                    }
                }
            }
        }
    }

    private var orderedIDs: [Int64] {
        let ordered = viewModel.messages.map(\.id).filter { ids.contains($0) }
        return ordered.isEmpty ? Array(ids) : ordered
    }

    private var anyUnread: Bool {
        viewModel.messages.contains { ids.contains($0.id) && !$0.isRead }
    }

    private var singleDraft: StoredMessage? {
        guard orderedIDs.count == 1 else { return nil }
        return viewModel.messages.first { $0.id == orderedIDs[0] && $0.folder == .drafts }
    }

    private var replyID: Int64? {
        viewModel.focusedMessageID(in: ids)
    }

    private func compose(_ request: ComposeRequest, id: Int64) {
        Task {
            await viewModel.selectMessage(id)
            viewModel.openCompose(request)
        }
    }
}
