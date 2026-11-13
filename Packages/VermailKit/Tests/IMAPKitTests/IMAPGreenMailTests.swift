import Foundation
import IMAPKit
import SMTPKit
import Testing

@Suite(.greenMail, .timeLimit(.minutes(1)))
struct IMAPGreenMailTests {
    @Test func sendMessageAndReadBackViaIMAP() async throws {
        let marker = UUID().uuidString
        let smtp = SMTPClient(configuration: .init(host: "localhost", port: 3025, security: .none, timeout: 5))
        defer { Task { await smtp.close() } }
        try await smtp.connect()
        try await smtp.send(.init(
            from: "alice@localhost",
            recipients: ["test@localhost"],
            data: Data("Subject: Vermail IMAP Test\r\n\r\nbody \(marker)".utf8)
        ))

        let client = IMAPClient(configuration: .init(host: "localhost", port: 3143, security: .none, timeout: 5))
        defer { Task { await client.close() } }
        try await client.authenticate(credentials: .init(username: "test@localhost", password: "test"))
        let boxes = try await client.remoteMailboxes()
        #expect(boxes.contains { $0.folder == .inbox })

        let refs = try await client.listMessages()
        var found = false
        for ref in refs.reversed().prefix(15) {
            let data = try await client.fetchMessage(ref)
            if String(decoding: data, as: UTF8.self).contains(marker) {
                found = true
                break
            }
        }
        #expect(found)
    }
}
