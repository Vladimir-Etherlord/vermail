import MailCore
import Testing

struct MailFolderKindTests {
    @Test func rawValuesAreStableForPersistence() {
        #expect(MailFolderKind.allCases.map(\.rawValue) == [
            "inbox", "drafts", "sent", "trash", "spam", "archive", "allMail",
        ])
    }
}
