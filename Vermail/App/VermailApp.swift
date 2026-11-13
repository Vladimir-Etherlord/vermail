import MailCore
import MailStorage
import SwiftUI

@main
struct VermailApp: App {
    @State private var viewModel: MainWindowViewModel

    init() {
        let database: MailDatabase
        do {
            database = try MailStorage.open()
        } catch {
            let fallbackRoot = FileManager.default.temporaryDirectory
                .appending(path: "VermailFallback", directoryHint: .isDirectory)
            // swiftlint:disable:next force_try
            database = try! MailDatabase(rootDirectory: fallbackRoot)
        }

        let accountStore = AccountStore()
        let secretStore = KeychainSecretStore()
        let identityStore = ComposeIdentityStore()
        let preferencesStore = AppPreferencesStore()
        let syncEngine = MailSyncEngine(database: database, secretStore: secretStore)
        let sendService = MailSendService(database: database, secretStore: secretStore)
        _viewModel = State(initialValue: MainWindowViewModel(
            database: database,
            accountStore: accountStore,
            syncEngine: syncEngine,
            identityStore: identityStore,
            sendService: sendService,
            secretStore: secretStore,
            preferencesStore: preferencesStore,
            systemServices: .live
        ))
    }

    var body: some Scene {
        WindowGroup {
            MainWindowView(viewModel: viewModel)
                .environment(viewModel.preferencesStore)
        }
        .defaultSize(width: 1200, height: 760)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Vermail") {
                    AboutWindowPresenter.shared.show()
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("New Message") {
                    viewModel.openCompose(.newMessage)
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(viewModel.accounts.filter(\.isEnabled).isEmpty)
            }
            CommandMenu("Message") {
                Button("Reply") {
                    viewModel.openCompose(.reply)
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(viewModel.selectedMessage == nil)

                Button("Reply All") {
                    viewModel.openCompose(.replyAll)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(viewModel.selectedMessage == nil)

                Button("Forward") {
                    viewModel.openCompose(.forward)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(viewModel.selectedMessage == nil)

                Divider()

                Button("Archive") {
                    guard let id = viewModel.selectedMessageID else { return }
                    Task { await viewModel.move(ids: [id], to: .archive) }
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(viewModel.selectedMessage == nil)

                Button("Delete") {
                    guard let id = viewModel.selectedMessageID else { return }
                    viewModel.requestDelete([id])
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(viewModel.selectedMessage == nil)
            }
        }

        Settings {
            SettingsView(viewModel: viewModel)
                .environment(viewModel.preferencesStore)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 920, height: 640)
    }
}
