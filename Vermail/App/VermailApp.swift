import SwiftUI

@main
struct VermailApp: App {
    var body: some Scene {
        WindowGroup {
            MainWindowView()
        }
        .defaultSize(width: 1200, height: 760)

        Settings {
            SettingsView()
        }
    }
}
