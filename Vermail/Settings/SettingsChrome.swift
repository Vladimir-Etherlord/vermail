import AppKit
import SwiftUI

enum SettingsChrome {
    /// Same gray window fill Mail and System Settings use, instead of pure white.
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
}

extension View {
    func settingsWindow(minSize: CGSize) -> some View {
        frame(minWidth: minSize.width, maxWidth: .infinity, minHeight: minSize.height, maxHeight: .infinity)
            .background(SettingsChrome.canvas)
            .background(WindowResizeEnabler(minSize: minSize, usesSystemWindowBackground: true))
    }

    func settingsForm() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(SettingsChrome.canvas)
    }
}
