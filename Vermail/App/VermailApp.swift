import AppKit
import MailCore
import MailStorage
import SwiftUI

@main
struct VermailApp: App {
    @State private var viewModel: MainWindowViewModel

    init() {
        let fallbackRoot = FileManager.default.temporaryDirectory
            .appending(path: "VermailFallback", directoryHint: .isDirectory)
        let database: MailDatabase
        do {
            let root = try MailStorage.defaultRootDirectory()
            try StorageBootstrap.adoptFallbackMailbox(into: root, fallbackRoot: fallbackRoot)
            database = try MailStorage.open(rootDirectory: root)
        } catch {
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
                .task {
                    await AppUpdateController.shared.checkIfDue(store: viewModel.preferencesStore)
                    let center = NotificationCenter.default
                    for await _ in center.notifications(named: NSApplication.didBecomeActiveNotification) {
                        await AppUpdateController.shared.checkIfDue(store: viewModel.preferencesStore)
                    }
                }
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
                    let ids = viewModel.idsForListActions()
                    guard !ids.isEmpty else { return }
                    Task { await viewModel.move(ids: ids, to: .archive) }
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(viewModel.idsForListActions().isEmpty)

                Button("Delete") {
                    let ids = viewModel.idsForListActions()
                    guard !ids.isEmpty else { return }
                    viewModel.requestDelete(ids)
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(viewModel.idsForListActions().isEmpty)
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
