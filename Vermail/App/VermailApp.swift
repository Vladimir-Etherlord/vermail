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
            preferencesStore: preferencesStore
        ))
    }

    var body: some Scene {
        WindowGroup {
            MainWindowView(viewModel: viewModel)
                .environment(viewModel.preferencesStore)
        }
        .defaultSize(width: 1200, height: 760)

        Settings {
            SettingsView(viewModel: viewModel)
                .environment(viewModel.preferencesStore)
        }
    }
}
