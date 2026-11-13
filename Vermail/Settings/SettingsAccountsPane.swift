import MailCore
import SwiftUI

struct SettingsAccountsPane: View {
    @Bindable var viewModel: MainWindowViewModel
    @State private var editorDraft: AccountDraft?
    @State private var showingWizard = false
    @State private var pendingDelete: MailAccount?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.accounts.isEmpty {
                ContentUnavailableView("No Accounts", systemImage: "person.crop.circle.badge.plus")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.accounts) { account in
                    HStack(spacing: 10) {
                        Image(systemName: account.details?.symbolName ?? "envelope.fill")
                            .foregroundStyle(AccountAppearance.color(named: account.details?.colorName))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: account.displayName)
                            Text(verbatim: account.emailAddress)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit") { edit(account) }
                    }
                    .contextMenu {
                        Button("Delete Account", role: .destructive) { pendingDelete = account }
                    }
                    .listRowBackground(SettingsChrome.card)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SettingsChrome.canvas)
        .navigationTitle(Text("Accounts"))
        .toolbar {
            Button("Add Account", systemImage: "plus") { showingWizard = true }
        }
        .sheet(isPresented: $showingWizard) {
            AccountWizardView(viewModel: viewModel)
        }
        .sheet(item: $editorDraft) { draft in
            AccountEditorView(viewModel: viewModel, draft: draft)
        }
        .alert("Delete Account?", isPresented: deletePresented) {
            Button("Delete", role: .destructive) {
                guard let account = pendingDelete else { return }
                Task { await remove(account) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Messages already downloaded stay on this Mac. The password is removed from the Keychain.")
        }
        .alert("Could Not Save", isPresented: errorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: errorMessage ?? "")
        }
    }

    private var deletePresented: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: {
            if !$0 {
                pendingDelete = nil
            }
        })
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: {
            if !$0 {
                errorMessage = nil
            }
        })
    }

    private func edit(_ account: MailAccount) {
        Task {
            do {
                editorDraft = try await viewModel.accountDraft(for: account)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func remove(_ account: MailAccount) async {
        do {
            try await viewModel.deleteAccount(id: account.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum AccountAppearance {
    static let symbols = [
        "envelope.fill",
        "tray.fill",
        "person.fill",
        "star.fill",
        "briefcase.fill",
        "house.fill",
        "heart.fill",
        "book.fill",
    ]
    static let colorNames = ["blue", "green", "orange", "purple", "pink", "teal", "red", "gray"]

    static func color(named name: String?) -> Color {
        switch name {
        case "green": .green
        case "orange": .orange
        case "purple": .purple
        case "pink": .pink
        case "teal": .teal
        case "red": .red
        case "gray": .gray
        default: .blue
        }
    }

    static func title(forColor name: String) -> LocalizedStringResource {
        switch name {
        case "green": "Green"
        case "orange": "Orange"
        case "purple": "Purple"
        case "pink": "Pink"
        case "teal": "Teal"
        case "red": "Red"
        case "gray": "Gray"
        default: "Blue"
        }
    }
}
