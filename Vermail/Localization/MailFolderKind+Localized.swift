import MailCore
import SwiftUI

extension MailFolderKind {
    var title: LocalizedStringResource {
        switch self {
        case .inbox: "Inbox"
        case .drafts: "Drafts"
        case .sent: "Sent"
        case .trash: "Trash"
        case .spam: "Spam"
        case .archive: "Archive"
        case .allMail: "All Mail"
        }
    }

    var systemImage: String {
        switch self {
        case .inbox: "tray"
        case .drafts: "doc"
        case .sent: "paperplane"
        case .trash: "trash"
        case .spam: "xmark.bin"
        case .archive: "archivebox"
        case .allMail: "tray.2"
        }
    }
}
