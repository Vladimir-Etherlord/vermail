import Foundation
import MailCore
import MailStorage
import Testing

struct HeaderRepairTests {
    @Test func rewritingHeadersKeepsTheReadFlag() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "HeaderRepair-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try MailDatabase(rootDirectory: root)
        let account = MailAccount(displayName: "Mail", emailAddress: "user@example.com", incomingProtocol: .pop3)
        let stored = try await database.upsertMessage(.init(
            accountID: account.id,
            remoteUID: "uid",
            folder: .inbox,
            subject: "=?utf-8?B?0J/RgNC40LLQtdGC?=",
            fromAddress: "=?utf-8?Q?=D0=90=D0=BD=D0=BD=D0=B0?= <a@example.com>",
            toAddresses: ["user@example.com"],
            snippet: "hello",
            receivedAt: Date(),
            isRead: true,
            rawSource: Data("Body".utf8)
        ))

        let pending = try await database.messageIDsWithEncodedWords()
        #expect(pending == [stored.id])
        try await database.updateDecodedHeaders(
            id: stored.id,
            subject: "Привет",
            fromAddress: "Анна <a@example.com>",
            toAddresses: ["user@example.com"],
            snippet: "hello"
        )

        let messages = try await database.messages(in: Mailbox(folder: .inbox), accounts: [account])
        #expect(messages.map(\.subject) == ["Привет"])
        #expect(messages.map(\.fromAddress) == ["Анна <a@example.com>"])
        #expect(messages.map(\.isRead) == [true])
        #expect(try await database.messageIDsWithEncodedWords().isEmpty)
    }
}
