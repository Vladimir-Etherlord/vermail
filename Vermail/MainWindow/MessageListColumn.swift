import MailCore
import MailStorage
import SwiftUI

/// The folder title and New Message stay in the list column, apart from actions on the open message.
struct MessageListColumn: View {
    @Bindable var viewModel: MainWindowViewModel
    var requestDelete: ([Int64]) -> Void

    var body: some View {
        VStack(spacing: 0) {
            mailboxHeading
            messageList
        }
        .searchable(text: searchBinding, placement: .toolbar)
        .toolbar {
            ToolbarItem(placement: .automatic) {
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

    private var mailboxHeading: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(viewModel.selectedMailbox.folder.title)
                .font(.title2.bold())
            Spacer(minLength: 8)
            Button("New Message", systemImage: "square.and.pencil") {
                viewModel.openCompose(.newMessage)
            }
            .help("New Message")
            .disabled(viewModel.accounts.filter(\.isEnabled).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private var searchBinding: Binding<String> {
        Binding(
            get: { viewModel.searchQuery },
            set: { viewModel.updateSearchQuery($0) }
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
                .contextMenu {
                    Button(message.isRead ? "Mark as Unread" : "Mark as Read") {
                        Task { await viewModel.toggleRead(ids: [message.id]) }
                    }
                    if message.folder == .drafts {
                        Button("Edit Draft") {
                            Task {
                                await viewModel.selectMessage(message.id)
                                viewModel.openCompose(.editDraft)
                            }
                        }
                    }
                    Button("Reply") {
                        Task {
                            await viewModel.selectMessage(message.id)
                            viewModel.openCompose(.reply)
                        }
                    }
                    Button("Reply All") {
                        Task {
                            await viewModel.selectMessage(message.id)
                            viewModel.openCompose(.replyAll)
                        }
                    }
                    Button("Forward") {
                        Task {
                            await viewModel.selectMessage(message.id)
                            viewModel.openCompose(.forward)
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
                        requestDelete([message.id])
                    }
                }
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
