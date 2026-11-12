import Foundation
import MailCore
import Testing

struct MailAccountCodingTests {
    @Test func decodesAccountSavedBeforeDetailsExisted() throws {
        let id = UUID()
        let json = """
        {
          "displayName": "Mail.ru",
          "emailAddress": "user@mail.ru",
          "id": "\(id.uuidString)",
          "incomingProtocol": "pop3",
          "isEnabled": true,
          "isIncludedInUnifiedFolders": true
        }
        """

        let account = try JSONDecoder().decode(MailAccount.self, from: Data(json.utf8))
        #expect(account.id == id)
        #expect(account.details == nil)
        #expect(account.incomingLogin == "user@mail.ru")
        #expect(!account.allowsInvalidCertificates)
    }

    @Test func roundtripsAccountDetails() throws {
        let account = MailAccount(
            displayName: "Work",
            emailAddress: "work@example.com",
            incomingProtocol: .pop3,
            details: AccountDetails(
                summary: "Office",
                incomingUsername: "work",
                allowsInvalidCertificates: true,
                checkIntervalMinutes: 15,
                deleteFromServerAfterDays: 14
            )
        )

        let data = try JSONEncoder().encode(account)
        let decoded = try JSONDecoder().decode(MailAccount.self, from: data)
        #expect(decoded == account)
        #expect(decoded.incomingLogin == "work")
    }
}
