import MailCore
import MailStorage
import SwiftUI

struct MainWindowView: View {
    @Bindable var viewModel: MainWindowViewModel

    var body: some View {
        NavigationSplitView {
            MailboxSidebar(
                accounts: viewModel.accounts,
                unreadCounts: viewModel.unreadCounts,
                syncStates: viewModel.syncStates,
                showsUnifiedFolders: viewModel.preferencesStore.preferences.unifyInboxes,
                selection: mailboxSelectionBinding,
                onEmptyTrash: { viewModel.requestEmptyTrash($0) }
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
            MessageListColumn(viewModel: viewModel) { requestDelete($0) }
                .navigationTitle(Text(viewModel.selectedMailbox.folder.title))
                .toolbarRole(.editor)
                .navigationSplitViewColumnWidth(min: 290, ideal: 350)
        } detail: {
            Group {
                if let message = viewModel.selectedMessage {
                    MessageDetailView(
                        message: message,
                        parsedMessage: viewModel.selectedParsedMessage,
                        currentFolder: viewModel.selectedMailbox.folder,
                        shouldShowRemoteImageBanner: viewModel.shouldShowRemoteImageBanner,
                        allowRemoteImages: viewModel.isRemoteImagesAllowedForSelectedMessage,
                        onAllowImagesOnce: { viewModel.allowRemoteImagesOnce() },
                        onAllowImagesAlways: { viewModel.allowRemoteImagesAlways() }
                    )
                } else {
                    ContentUnavailableView("No Message Selected", systemImage: "envelope")
                }
            }
            .toolbar {
                MessageToolbar(viewModel: viewModel) {
                    let ids = viewModel.idsForListActions()
                    if !ids.isEmpty {
                        requestDelete(ids)
                    }
                }
            }
        }
        .background(WindowFrameAutosave(name: "VermailMain", iconOnlyToolbar: true))
        .task {
            await viewModel.loadInitialData()
            viewModel.startSystemServices()
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
        .alert("Delete Messages?", isPresented: deletePresented) {
            Button("Delete", role: .destructive) {
                let ids = viewModel.pendingDeleteIDs
                viewModel.pendingDeleteIDs = []
                viewModel.isDeleteConfirmationPresented = false
                Task { await viewModel.delete(ids: ids) }
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelPendingDelete()
            }
        } message: {
            Text("This moves the selected messages to the Trash. Messages already in the Trash are deleted.")
        }
        .alert("Empty Trash?", isPresented: emptyTrashPresented) {
            Button("Empty Trash", role: .destructive) {
                let mailbox = viewModel.pendingEmptyTrash
                viewModel.pendingEmptyTrash = nil
                viewModel.isEmptyTrashConfirmationPresented = false
                guard let mailbox else { return }
                Task { await viewModel.emptyTrash(mailbox) }
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingEmptyTrash = nil
            }
        } message: {
            Text("This permanently deletes every message in this Trash.")
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

    private var deletePresented: Binding<Bool> {
        // The alert clears `isPresented` before the Delete button runs. Keep the ids until that button copies them.
        Binding(
            get: { viewModel.isDeleteConfirmationPresented },
            set: { viewModel.isDeleteConfirmationPresented = $0 }
        )
    }

    private var emptyTrashPresented: Binding<Bool> {
        Binding(
            get: { viewModel.isEmptyTrashConfirmationPresented },
            set: { viewModel.isEmptyTrashConfirmationPresented = $0 }
        )
    }

    private func requestDelete(_ ids: [Int64]) {
        viewModel.requestDelete(ids)
    }
}

/// Unified folders first; per-account folders only make sense once there is more than one account.
private struct MailboxSidebar: View {
    let accounts: [MailAccount]
    let unreadCounts: UnreadCounts
    let syncStates: [UUID: AccountSyncState]
    let showsUnifiedFolders: Bool
    @Binding var selection: Mailbox?
    var onEmptyTrash: (Mailbox) -> Void

    var body: some View {
        List(selection: $selection) {
            if showsUnifiedFolders {
                Section("All Accounts") {
                    folderRows(scope: .unified)
                }
            }
            if !showsUnifiedFolders || accounts.count > 1 {
                ForEach(accounts) { account in
                    Section {
                        folderRows(scope: .account(account.id))
                    } header: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(AccountAppearance.color(named: account.details?.colorName))
                                .frame(width: 8, height: 8)
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
            .contextMenu {
                if folder == .trash {
                    Button("Empty Trash", role: .destructive) {
                        onEmptyTrash(mailbox)
                    }
                }
            }
        }
    }
}
