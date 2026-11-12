import MailCore
import MailStorage
import SwiftUI

struct MainWindowView: View {
    @Bindable var viewModel: MainWindowViewModel
    @State private var composeModel: ComposeViewModel?

    var body: some View {
        NavigationSplitView {
            MailboxSidebar(
                accounts: viewModel.accounts,
                unreadCounts: viewModel.unreadCounts,
                syncStates: viewModel.syncStates,
                selection: mailboxSelectionBinding
            )
            .navigationSplitViewColumnWidth(min: 190, ideal: 230)
            .toolbar {
                ToolbarItem {
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        if viewModel.isSyncing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(viewModel.isSyncing || viewModel.accounts.isEmpty)
                    .help("Check for New Mail")
                }
            }
        } content: {
            messageListColumn
                .navigationTitle(Text(viewModel.selectedMailbox.folder.title))
                .navigationSplitViewColumnWidth(min: 290, ideal: 350)
        } detail: {
            if let message = viewModel.selectedMessage {
                MessageDetailView(
                    message: message,
                    parsedMessage: viewModel.selectedParsedMessage,
                    currentFolder: viewModel.selectedMailbox.folder,
                    shouldShowRemoteImageBanner: viewModel.shouldShowRemoteImageBanner,
                    allowRemoteImages: viewModel.isRemoteImagesAllowedForSelectedMessage,
                    onAllowImagesOnce: { viewModel.allowRemoteImagesOnce() },
                    onAllowImagesAlways: { viewModel.allowRemoteImagesAlways() },
                    onToggleRead: { Task { await viewModel.toggleRead(ids: [message.id]) } },
                    onArchive: { Task { await viewModel.move(ids: [message.id], to: .archive) } },
                    onDelete: { Task { await viewModel.delete(ids: [message.id]) } },
                    onMove: { folder in Task { await viewModel.move(ids: [message.id], to: folder) } },
                    onReply: { openCompose(.reply) },
                    onReplyAll: { openCompose(.replyAll) },
                    onForward: { openCompose(.forward) },
                    onEditDraft: { openCompose(.editDraft) }
                )
            } else {
                ContentUnavailableView("No Message Selected", systemImage: "envelope")
            }
        }
        .task {
            await viewModel.loadInitialData()
        }
        .sheet(item: $composeModel) { model in
            ComposeView(model: model) {
                composeModel = nil
                Task { await viewModel.reloadMessages() }
            }
        }
        .alert(
            "Something Went Wrong",
            isPresented: Binding(
                get: { viewModel.lastError != nil },
                set: {
                    if !$0 {
                        viewModel.lastError = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: viewModel.lastError ?? "")
        }
    }

    private var mailboxSelectionBinding: Binding<Mailbox?> {
        Binding(
            get: { viewModel.selectedMailbox },
            set: { newValue in
                guard let newValue else { return }
                Task { await viewModel.selectMailbox(newValue) }
            }
        )
    }

    private var messageSelectionBinding: Binding<Int64?> {
        Binding(
            get: { viewModel.selectedMessageID },
            set: { newValue in
                Task { await viewModel.selectMessage(newValue) }
            }
        )
    }

    private var searchBinding: Binding<String> {
        Binding(
            get: { viewModel.searchQuery },
            set: { viewModel.updateSearchQuery($0) }
        )
    }

    private var messageListColumn: some View {
        Group {
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
                        accountColor: accountMarkerColor(for: message.accountID)
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
                            Task { await viewModel.delete(ids: [message.id]) }
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
                    .contextMenu {
                        Button(message.isRead ? "Mark as Unread" : "Mark as Read") {
                            Task { await viewModel.toggleRead(ids: [message.id]) }
                        }
                        if message.folder == .drafts {
                            Button("Edit Draft") {
                                Task {
                                    await viewModel.selectMessage(message.id)
                                    openCompose(.editDraft)
                                }
                            }
                        }
                        Button("Archive") {
                            Task { await viewModel.move(ids: [message.id], to: .archive) }
                        }
                        Menu("Move to Folder") {
                            ForEach(MailFolderKind.allCases, id: \.self) { folder in
                                if folder != .allMail {
                                    Button {
                                        Task { await viewModel.move(ids: [message.id], to: folder) }
                                    } label: {
                                        Text(folder.title)
                                    }
                                }
                            }
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            Task { await viewModel.delete(ids: [message.id]) }
                        }
                    }
                }
            }
        }
        .searchable(text: searchBinding, placement: .toolbar)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    openCompose(.newMessage)
                } label: {
                    Label("Compose", systemImage: "square.and.pencil")
                }
                .help("New Message")

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
                .help("Show Unread Messages Only")
            }
        }
    }

    private func accountMarkerColor(for accountID: UUID) -> Color? {
        guard case .unified = viewModel.selectedMailbox.scope, viewModel.accounts.count > 1 else {
            return nil
        }
        let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal]
        guard let index = viewModel.accounts.firstIndex(where: { $0.id == accountID }) else {
            return nil
        }
        return palette[index % palette.count]
    }

    private func openCompose(_ request: ComposeRequest) {
        guard let model = viewModel.makeComposeViewModel(for: request) else {
            viewModel.lastError = String(localized: "Add an account before composing.")
            return
        }
        composeModel = model
    }
}

/// Unified folders first; per-account folders only make sense once there is more than one account.
private struct MailboxSidebar: View {
    let accounts: [MailAccount]
    let unreadCounts: UnreadCounts
    let syncStates: [UUID: AccountSyncState]
    @Binding var selection: Mailbox?

    var body: some View {
        List(selection: $selection) {
            Section("All Accounts") {
                folderRows(scope: .unified)
            }
            if accounts.count > 1 {
                ForEach(accounts) { account in
                    Section {
                        folderRows(scope: .account(account.id))
                    } header: {
                        HStack(spacing: 6) {
                            Text(verbatim: account.displayName)
                            if case .syncing = syncStates[account.id] {
                                ProgressView()
                                    .controlSize(.mini)
                            } else if case let .error(message) = syncStates[account.id] {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.yellow)
                                    .help(message)
                            }
                        }
                    }
                }
            }
        }
    }

    private func folderRows(scope: Mailbox.Scope) -> some View {
        ForEach(MailFolderKind.allCases, id: \.self) { folder in
            let mailbox = Mailbox(folder: folder, scope: scope)
            let unread = unreadCounts.count(for: mailbox)
            Label {
                Text(folder.title)
            } icon: {
                Image(systemName: folder.systemImage)
            }
            .badge(unread)
            .tag(mailbox)
        }
    }
}
