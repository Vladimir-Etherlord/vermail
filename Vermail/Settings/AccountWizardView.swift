import MailCore
import SwiftUI

struct AccountWizardView: View {
    @Bindable var viewModel: MainWindowViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = AccountDraft.makeNew()
    @State private var statusMessage = ""
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var offersAppPassword = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Account")
                .font(.title2.bold())
            TextField("Email", text: $draft.emailAddress)
                .textFieldStyle(.roundedBorder)
            HStack {
                TextField("Full Name", text: $draft.displayName)
                Button("Detect Servers") { Task { await detect() } }
                    .disabled(isWorking)
            }
            serverFields
            if offersAppPassword {
                Picker("Sign-In", selection: credentialChoice) {
                    Text("App Password").tag(AccountCredentialChoice.appPassword)
                    Text("Access Token").tag(AccountCredentialChoice.accessToken)
                }
                .pickerStyle(.segmented)
                Text(
                    """
                    Gmail and Outlook accept an access token or an app password. \
                    The same secret is used for receiving and sending.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            SecureField(secretTitle, text: $draft.incomingSecret)
            if !statusMessage.isEmpty {
                Text(verbatim: statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking)
            }
        }
        .padding(20)
        .frame(minWidth: 560, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
        .background(WindowResizeEnabler(minSize: CGSize(width: 560, height: 420)))
        .alert("Could Not Save", isPresented: errorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: errorMessage ?? "")
        }
    }

    private var secretTitle: LocalizedStringResource {
        draft.incomingAuthentication == .xoauth2 ? "Access Token" : "Password"
    }

    private var credentialChoice: Binding<AccountCredentialChoice> {
        Binding(
            get: {
                draft.incomingAuthentication == .xoauth2 ? .accessToken : .appPassword
            },
            set: { choice in
                draft = draft.applyingCredentialChoice(choice)
            }
        )
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: {
            if !$0 {
                errorMessage = nil
            }
        })
    }

    private var serverFields: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                Text("Incoming Server")
                TextField("Host", text: $draft.incomingHost)
                TextField("Port", value: $draft.incomingPort, format: .number)
                    .frame(width: 70)
            }
            GridRow {
                Text("Outgoing Server")
                TextField("Host", text: $draft.outgoingHost)
                TextField("Port", value: $draft.outgoingPort, format: .number)
                    .frame(width: 70)
            }
        }
    }

    private func detect() async {
        let email = draft.emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.contains("@") else {
            statusMessage = String(localized: "Enter a valid email address.")
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await MailAutoconfigService().configure(emailAddress: email)
            guard let result else {
                statusMessage = String(localized: "No server settings were found. Enter them manually.")
                return
            }
            draft = draft.applyingDiscovery(result)
            offersAppPassword = draft.incomingAuthentication == .xoauth2 || draft.outgoingAuthentication == .xoauth2
            if draft.incomingUsername.isEmpty {
                draft.incomingUsername = email
            }
            if draft.outgoingUsername.isEmpty {
                draft.outgoingUsername = email
            }
            statusMessage = String(localized: "Server settings were filled in.")
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func save() async {
        isWorking = true
        defer { isWorking = false }
        draft.outgoingSecret = draft.incomingSecret
        draft.displayName = draft.displayName.isEmpty ? draft.emailAddress : draft.displayName
        do {
            try await viewModel.saveAccount(draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
