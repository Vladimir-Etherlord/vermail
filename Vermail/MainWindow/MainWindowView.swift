import MailCore
import SwiftUI

struct MainWindowView: View {
    @State private var selectedFolder: MailFolderKind? = .inbox

    var body: some View {
        NavigationSplitView {
            List(MailFolderKind.allCases, id: \.self, selection: $selectedFolder) { folder in
                Label {
                    Text(folder.title)
                } icon: {
                    Image(systemName: folder.systemImage)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } content: {
            ContentUnavailableView("No Messages", systemImage: "tray")
                .navigationTitle(Text(selectedFolder?.title ?? "Inbox"))
                .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        } detail: {
            ContentUnavailableView("No Message Selected", systemImage: "envelope")
        }
    }
}

#Preview {
    MainWindowView()
}
