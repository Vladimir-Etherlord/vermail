/// Unified local folders. Messages from every account land in these folders regardless of protocol:
/// POP3 accounts only fill the inbox from the server, IMAP server folders are mapped onto these kinds.
public enum MailFolderKind: String, CaseIterable, Codable, Sendable {
    case inbox
    case drafts
    case sent
    case trash
    case spam
    case archive
    case allMail
}
