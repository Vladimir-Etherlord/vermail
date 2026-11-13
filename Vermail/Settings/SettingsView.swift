import MailCore
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case accounts
    case general
    case composing
    case appearance
    case messages

    var id: String {
        rawValue
    }

    var title: LocalizedStringResource {
        switch self {
        case .accounts: "Accounts"
        case .general: "General"
        case .composing: "Composing"
        case .appearance: "Appearance"
        case .messages: "Messages"
        }
    }

    var symbol: String {
        switch self {
        case .accounts: "person.2"
        case .general: "gearshape"
        case .composing: "square.and.pencil"
        case .appearance: "paintbrush"
        case .messages: "envelope"
        }
    }
}

struct SettingsView: View {
    @Bindable var viewModel: MainWindowViewModel
    @State private var section: SettingsSection? = .accounts

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $section) { item in
                Label {
                    Text(item.title)
                } icon: {
                    Image(systemName: item.symbol)
                }
                .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch section ?? .accounts {
            case .accounts:
                SettingsAccountsPane(viewModel: viewModel)
            case .general:
                GeneralSettingsPane(store: viewModel.preferencesStore)
            case .composing:
                ComposingSettingsPane(store: viewModel.preferencesStore, accounts: viewModel.accounts)
            case .appearance:
                AppearanceSettingsPane(store: viewModel.preferencesStore)
            case .messages:
                MessagesSettingsPane(store: viewModel.preferencesStore)
            }
        }
        .frame(minWidth: 760, maxWidth: .infinity, minHeight: 540, maxHeight: .infinity)
        .background(WindowResizeEnabler(minSize: CGSize(width: 760, height: 540)))
        .task {
            await viewModel.loadInitialData()
        }
        .onChange(of: viewModel.preferencesStore.preferences.showDockBadge) {
            viewModel.applyDockBadge()
        }
        .onChange(of: viewModel.preferencesStore.preferences.showMenuBarIcon) {
            viewModel.applyDockBadge()
        }
        .onChange(of: viewModel.preferencesStore.preferences.notificationsEnabled) {
            viewModel.requestNotificationAuthorizationIfNeeded()
        }
    }
}

private struct GeneralSettingsPane: View {
    @Bindable var store: AppPreferencesStore
    @State private var language = AppLanguage.current()
    @State private var choosingFolder = false

    private let readDelays: [Double] = [0, 0.5, 1, 2, 5]

    var body: some View {
        Form {
            Picker("Language:", selection: $language) {
                ForEach([AppLanguage.system] + AppLanguage.available()) { item in
                    if let nativeName = item.nativeName {
                        Text(verbatim: nativeName).tag(item)
                    } else {
                        Text("System").tag(item)
                    }
                }
            }
            .onChange(of: language) { _, newValue in
                newValue.apply()
            }
            Text("Requires restart")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Unified Inbox", isOn: $store.preferences.unifyInboxes)
            Toggle("Play Sounds", isOn: $store.preferences.playSounds)
            Toggle("Show Dock Badge", isOn: $store.preferences.showDockBadge)
            Toggle("Show Menu Bar Icon", isOn: $store.preferences.showMenuBarIcon)
            Toggle("Enable Notifications", isOn: $store.preferences.notificationsEnabled)
            Picker("Mark as Read", selection: $store.preferences.markAsReadDelaySeconds) {
                ForEach(readDelays, id: \.self) { delay in
                    Text(readDelayTitle(delay)).tag(delay)
                }
            }
            LabeledContent("Attachment Folder") {
                HStack {
                    Text(verbatim: store.preferences.attachmentFolderPath ?? String(localized: "Ask Every Time"))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…") { choosingFolder = true }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text("General"))
        .onChange(of: store.preferences) { store.save() }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            storeAttachmentFolder(result)
        }
    }

    private func readDelayTitle(_ delay: Double) -> LocalizedStringResource {
        switch delay {
        case 0: "Immediately"
        case 0.5: "After 0.5 seconds"
        case 1: "After 1 second"
        case 2: "After 2 seconds"
        default: "After 5 seconds"
        }
    }

    private func storeAttachmentFolder(_ result: Result<URL, Error>) {
        guard case let .success(url) = result else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        store.preferences.attachmentFolderPath = url.path(percentEncoded: false)
        store.preferences.attachmentFolderBookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        store.save()
    }
}

private struct ComposingSettingsPane: View {
    @Bindable var store: AppPreferencesStore
    let accounts: [MailAccount]

    var body: some View {
        Form {
            Picker("Default Account", selection: defaultAccountBinding) {
                Text("Automatic").tag(UUID?.none)
                ForEach(accounts) { account in
                    Text(verbatim: account.displayName).tag(Optional(account.id))
                }
            }
            Toggle("Include Signature", isOn: $store.preferences.includeSignature)
            Stepper(value: $store.preferences.composeFontSize, in: 11 ... 22, step: 1) {
                LabeledContent("Font Size") {
                    Text(verbatim: Int(store.preferences.composeFontSize).formatted())
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text("Composing"))
        .onChange(of: store.preferences) { store.save() }
    }

    private var defaultAccountBinding: Binding<UUID?> {
        Binding(
            get: { store.preferences.defaultAccountID },
            set: { store.preferences.defaultAccountID = $0 }
        )
    }
}

private struct AppearanceSettingsPane: View {
    @Bindable var store: AppPreferencesStore

    var body: some View {
        Form {
            Toggle("Show Avatars", isOn: $store.preferences.showAvatars)
            Toggle("Show Message Preview", isOn: $store.preferences.showMessagePreview)
        }
        .formStyle(.grouped)
        .navigationTitle(Text("Appearance"))
        .onChange(of: store.preferences) { store.save() }
    }
}

private struct MessagesSettingsPane: View {
    @Bindable var store: AppPreferencesStore

    var body: some View {
        Form {
            Toggle("Ask Before Deleting", isOn: $store.preferences.confirmDelete)
            VStack(alignment: .leading, spacing: 4) {
                Text("Sounds, the Dock badge, and notifications follow the switches in General.")
                Text("Mail is checked on each account's interval and again when the Mac wakes.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .navigationTitle(Text("Messages"))
        .onChange(of: store.preferences) { store.save() }
    }
}
