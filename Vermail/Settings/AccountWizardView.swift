import MailCore
import SwiftUI

struct AccountWizardView: View {
    @Bindable var viewModel: MainWindowViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = AccountDraft.makeNew()
    @State private var statusMessage = ""
    @State private var errorMessage: String?
    @State private var isWorking = false

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
            SecureField(secretTitle, text: $draft.incomingSecret)
            if draft.incomingAuthentication == .xoauth2 {
                Text(
                    """
                    Gmail and Outlook use an access token. \
                    Password sign-in can be chosen after the account is created.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
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
        .frame(width: 560)
        .alert("Could Not Save", isPresented: errorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: errorMessage ?? "")
        }
    }

    private var secretTitle: LocalizedStringResource {
        draft.incomingAuthentication == .xoauth2 ? "Access Token" : "Password"
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
