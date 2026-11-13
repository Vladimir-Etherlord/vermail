import AppKit
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
                    AccountSettingsRow(account: account) { edit(account) }
                        .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 12))
                        .listRowBackground(AccountSettingsRow.background(for: account))
                        .contextMenu {
                            Button("Delete Account", role: .destructive) { pendingDelete = account }
                        }
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

private struct AccountSettingsRow: View {
    let account: MailAccount
    let edit: () -> Void

    private var tint: Color {
        AccountAppearance.color(named: account.details?.colorName)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.18))
                Image(systemName: account.details?.symbolName ?? "envelope.fill")
                    .foregroundStyle(tint)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: account.displayName)
                Text(verbatim: account.emailAddress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Edit", action: edit)
        }
        .padding(.vertical, 6)
    }

    static func background(for account: MailAccount) -> some View {
        let tint = AccountAppearance.color(named: account.details?.colorName)
        return HStack(spacing: 0) {
            tint.opacity(0.75)
                .frame(width: 3)
            ZStack {
                SettingsChrome.card
                tint.opacity(0.07)
            }
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
        Color(nsColor: nsColor(named: name))
    }

    static func nsColor(named name: String?) -> NSColor {
        switch name {
        case "green": .systemGreen
        case "orange": .systemOrange
        case "purple": .systemPurple
        case "pink": .systemPink
        case "teal": .systemTeal
        case "red": .systemRed
        case "gray": .systemGray
        default: .systemBlue
        }
    }

    /// Drawn circle, not a template symbol. Menu items recolor template images to black.
    static func menuSwatch(named name: String) -> NSImage {
        let side: CGFloat = 14
        let color = nsColor(named: name)
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            color.setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
            path.stroke()
            return true
        }
        image.isTemplate = false
        return image
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
