/// Local mailbox folders. POP3 only exposes the server inbox, so every other folder lives on this Mac.
public enum MailFolderKind: String, CaseIterable, Codable, Sendable {
    case inbox
    case drafts
    case sent
    case trash
    case spam
    case archive
    case allMail
}
