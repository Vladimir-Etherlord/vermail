import MailCore
import Testing

struct MailboxTests {
    private let pop3 = MailAccount(displayName: "Mail.ru", emailAddress: "a@mail.ru", incomingProtocol: .pop3)
    private let imap = MailAccount(displayName: "Gmail", emailAddress: "b@gmail.com", incomingProtocol: .imap)
    private let hidden = MailAccount(
        displayName: "Work",
        emailAddress: "c@example.com",
        incomingProtocol: .pop3,
        isIncludedInUnifiedFolders: false
    )

    @Test func unifiedMailboxCollectsAccountsOfAnyProtocol() {
        let inbox = Mailbox(folder: .inbox)
        #expect(inbox.includes(pop3))
        #expect(inbox.includes(imap))
        #expect(!inbox.includes(hidden))
    }

    @Test func accountMailboxShowsOnlyThatAccount() {
        let inbox = Mailbox(folder: .inbox, scope: .account(hidden.id))
        #expect(inbox.includes(hidden))
        #expect(!inbox.includes(pop3))
    }
}
