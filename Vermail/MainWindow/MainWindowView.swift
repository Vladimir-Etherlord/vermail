import MailCore
import SwiftUI

struct MainWindowView: View {
    var accounts: [MailAccount] = []

    @State private var selection: Mailbox? = Mailbox(folder: .inbox)

    var body: some View {
        NavigationSplitView {
            MailboxSidebar(accounts: accounts, selection: $selection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } content: {
            ContentUnavailableView("No Messages", systemImage: "tray")
                .navigationTitle(Text(selection?.folder.title ?? "Inbox"))
                .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        } detail: {
            ContentUnavailableView("No Message Selected", systemImage: "envelope")
        }
    }
}

/// Unified folders first; per-account folders only make sense once there is more than one account.
private struct MailboxSidebar: View {
    let accounts: [MailAccount]
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
                        Text(verbatim: account.displayName)
                    }
                }
            }
        }
    }

    private func folderRows(scope: Mailbox.Scope) -> some View {
        ForEach(MailFolderKind.allCases, id: \.self) { folder in
            Label {
                Text(folder.title)
            } icon: {
                Image(systemName: folder.systemImage)
            }
            .tag(Mailbox(folder: folder, scope: scope))
        }
    }
}

#Preview {
    MainWindowView(accounts: [
        MailAccount(displayName: "Mail.ru", emailAddress: "user@mail.ru", incomingProtocol: .pop3),
        MailAccount(displayName: "Gmail", emailAddress: "user@gmail.com", incomingProtocol: .imap),
    ])
}
