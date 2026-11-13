import MailCore
import SwiftUI

enum AccountEditorTab: String, CaseIterable, Identifiable {
    case user
    case folders
    case alias
    case signature
    case more

    var id: String {
        rawValue
    }

    var title: LocalizedStringResource {
        switch self {
        case .user: "User"
        case .folders: "Folders"
        case .alias: "Alias"
        case .signature: "Signature"
        case .more: "More"
        }
    }
}

struct AccountEditorView: View {
    @Bindable var viewModel: MainWindowViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AccountDraft
    @State private var tab: AccountEditorTab = .user
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var isWorking = false

    init(viewModel: MainWindowViewModel, draft: AccountDraft) {
        self.viewModel = viewModel
        _draft = State(initialValue: draft)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker(selection: $tab) {
                ForEach(AccountEditorTab.allCases) { item in
                    Text(item.title).tag(item)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(AccountAppearance.color(named: draft.colorName).opacity(0.08))
            Rectangle()
                .fill(AccountAppearance.color(named: draft.colorName).opacity(0.55))
                .frame(height: 2)
            ScrollView {
                tabContent
                    .padding(.horizontal)
                    .padding(.bottom)
            }
            .scrollContentBackground(.hidden)
            Divider()
            HStack {
                if let statusMessage {
                    Text(verbatim: statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking)
            }
            .padding()
        }
        .settingsWindow(minSize: CGSize(width: 640, height: 480), frameAutosaveName: "VermailAccountEditor")
        .alert("Could Not Save", isPresented: errorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .user:
            AccountUserTab(draft: $draft, isWorking: $isWorking, test: testConnection)
        case .folders:
            AccountFoldersTab()
        case .alias:
            AccountAliasTab(draft: $draft)
        case .signature:
            AccountSignatureTab(signature: $draft.signature)
        case .more:
            AccountMoreTab(draft: $draft)
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: {
            if !$0 {
                errorMessage = nil
            }
        })
    }

    private func save() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await viewModel.saveAccount(draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func testConnection(incoming: Bool) async {
        isWorking = true
        defer { isWorking = false }
        do {
            if incoming {
                let stored = await viewModel.storedSecret(
                    for: draft.id,
                    kind: draft.incomingAuthentication == .xoauth2 ? .oauthAccessToken : .incomingPassword
                )
                try await AccountConnectionTester.testIncoming(draft, storedSecret: stored)
                statusMessage = String(localized: "Incoming server connection succeeded.")
            } else {
                let stored = await viewModel.storedSecret(
                    for: draft.id,
                    kind: draft.outgoingAuthentication == .xoauth2 ? .oauthAccessToken : .outgoingPassword
                )
                try await AccountConnectionTester.testOutgoing(draft, storedSecret: stored)
                statusMessage = String(localized: "Outgoing server connection succeeded.")
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

private struct AccountUserTab: View {
    @Binding var draft: AccountDraft
    @Binding var isWorking: Bool
    let test: (Bool) async -> Void

    var body: some View {
        Form {
            identityFields
            incomingFields
            outgoingFields
            Toggle("Allow Invalid Certificates", isOn: $draft.allowsInvalidCertificates)
        }
        .settingsForm()
    }

    @ViewBuilder
    private var identityFields: some View {
        emphasizedField("Full Name", text: $draft.displayName)
        TextField("Description", text: $draft.summary)
        Picker("Icon", selection: $draft.symbolName) {
            ForEach(AccountAppearance.symbols, id: \.self) { symbol in
                Image(systemName: symbol).tag(symbol)
            }
        }
        LabeledContent("Account Color") {
            AccountColorMenu(selection: $draft.colorName)
                .frame(width: 168, height: 24)
        }
        emphasizedField("Email", text: $draft.emailAddress)
        Toggle("Show in Unified Inbox", isOn: $draft.isIncludedInUnifiedFolders)
        Toggle("Account Enabled", isOn: $draft.isEnabled)
    }

    @ViewBuilder
    private var incomingFields: some View {
        emphasizedField("Incoming Server", text: $draft.incomingHost)
        TextField("Port", value: $draft.incomingPort, format: .number)
        securityPicker(selection: $draft.incomingSecurity)
        authPicker(selection: $draft.incomingAuthentication)
        TextField("Username", text: $draft.incomingUsername)
        SecureField(secretPrompt(stored: draft.hasStoredIncomingSecret), text: $draft.incomingSecret)
        Button("Test Incoming") { Task { await test(true) } }
            .disabled(isWorking)
    }

    @ViewBuilder
    private var outgoingFields: some View {
        emphasizedField("Outgoing Server", text: $draft.outgoingHost)
        TextField("Port", value: $draft.outgoingPort, format: .number)
        securityPicker(selection: $draft.outgoingSecurity)
        authPicker(selection: $draft.outgoingAuthentication)
        Toggle("Outgoing Authentication", isOn: $draft.outgoingRequiresAuthentication)
        TextField("Username", text: $draft.outgoingUsername)
        SecureField(secretPrompt(stored: draft.hasStoredOutgoingSecret), text: $draft.outgoingSecret)
        Button("Test Outgoing") { Task { await test(false) } }
            .disabled(isWorking)
    }

    private func securityPicker(selection: Binding<ServerSecurity>) -> some View {
        Picker("Security", selection: selection) {
            ForEach(ServerSecurity.allCases, id: \.self) { item in
                Text(item.menuTitle).tag(item)
            }
        }
    }

    private func authPicker(selection: Binding<ServerAuthenticationMethod>) -> some View {
        Picker("Authentication", selection: selection) {
            ForEach(ServerAuthenticationMethod.allCases, id: \.self) { item in
                Text(item.menuTitle).tag(item)
            }
        }
    }

    private func emphasizedField(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        LabeledContent {
            TextField(title, text: text)
                .labelsHidden()
        } label: {
            Text(title)
                .fontWeight(.semibold)
        }
    }

    private func secretPrompt(stored: Bool) -> LocalizedStringResource {
        stored ? "Password (leave blank to keep the saved one)" : "Password"
    }
}

extension ServerSecurity {
    var menuTitle: LocalizedStringResource {
        switch self {
        case .none: "None"
        case .ssl: "SSL"
        case .startTLS: "STARTTLS"
        }
    }
}

extension ServerAuthenticationMethod {
    var menuTitle: LocalizedStringResource {
        switch self {
        case .none: "None"
        case .userPassword: "Password"
        case .apop: "APOP"
        case .plain: "PLAIN"
        case .login: "LOGIN"
        case .cramMD5: "CRAM-MD5"
        case .xoauth2: "XOAUTH2"
        }
    }
}
