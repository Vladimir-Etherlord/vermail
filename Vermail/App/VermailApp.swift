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
        let syncEngine = MailSyncEngine(database: database, secretStore: secretStore)
        let sendService = MailSendService(database: database, secretStore: secretStore)
        _viewModel = State(initialValue: MainWindowViewModel(
            database: database,
            accountStore: accountStore,
            syncEngine: syncEngine,
            sendService: sendService
        ))
    }

    var body: some Scene {
        WindowGroup {
            MainWindowView(viewModel: viewModel)
        }
        .defaultSize(width: 1200, height: 760)

        Settings {
            SettingsView()
        }
    }
}
