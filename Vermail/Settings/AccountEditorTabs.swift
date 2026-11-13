import MailCore
import SwiftUI

struct AccountFoldersTab: View {
    var incomingProtocol: IncomingProtocol

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            folderExplanation
                .foregroundStyle(.secondary)
            ForEach(MailFolderKind.allCases, id: \.self) { folder in
                Label {
                    Text(folder.title)
                } icon: {
                    Image(systemName: folder.systemImage)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var folderExplanation: Text {
        if incomingProtocol == .imap {
            Text(
                "IMAP downloads Inbox, Sent, Drafts, Trash, Spam, and Archive when the server provides them."
            )
        } else {
            Text("POP3 downloads the inbox. Drafts, sent mail, trash, spam, and archive stay on this Mac.")
        }
    }
}

struct AccountAliasTab: View {
    @Binding var draft: AccountDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach($draft.aliases) { $alias in
                HStack {
                    TextField("Name", text: $alias.displayName)
                    TextField("Email", text: $alias.emailAddress)
                    Button(role: .destructive) {
                        draft.aliases.removeAll { $0.id == alias.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove Alias")
                }
            }
            Button("Add Alias") {
                draft.aliases.append(MailIdentity(accountID: draft.id, displayName: "", emailAddress: ""))
            }
        }
    }
}

struct AccountSignatureTab: View {
    @Binding var signature: String

    var body: some View {
        TextEditor(text: $signature)
            .font(.body)
            .frame(minHeight: 180)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
    }
}

struct AccountMoreTab: View {
    @Binding var draft: AccountDraft

    var body: some View {
        Form {
            Stepper(value: $draft.checkIntervalMinutes, in: 1 ... 1440) {
                LabeledContent("Check Interval (minutes)") {
                    Text(verbatim: draft.checkIntervalMinutes.formatted())
                }
            }
            if draft.incomingProtocol == .imap {
                Text("IMAP keeps mail on the server.")
                    .foregroundStyle(.secondary)
            } else {
                pop3Retention
            }
        }
        .settingsForm()
    }

    @ViewBuilder
    private var pop3Retention: some View {
        Toggle("Leave Mail on Server", isOn: $draft.leaveMailOnServer)
        retentionDays
        Toggle("Delete from Server When Emptied from Trash", isOn: $draft.deleteFromServerWhenDeletedLocally)
    }

    private var retentionDays: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Delete from Server After", isOn: $draft.deleteAfterDaysEnabled)
            HStack {
                Text("Days on Server")
                Spacer(minLength: 12)
                Text(verbatim: draft.deleteFromServerAfterDays.formatted())
                Stepper(value: $draft.deleteFromServerAfterDays, in: 1 ... 365) {
                    Text("Days on Server")
                }
                .labelsHidden()
            }
            .disabled(!draft.deleteAfterDaysEnabled)
            .padding(.leading, 22)
        }
    }
}
