import Foundation
import MailTransport
import POP3Kit
import SMTPKit
import Testing

struct SMTPTests {
    @Test(arguments: [(ConnectionSecurity.none, 25), (.startTLS, 587), (.ssl, 465)])
    func defaultPort(security: ConnectionSecurity, port: Int) {
        #expect(SMTP.defaultPort(for: security) == port)
    }

    @Test func loginAuthAndSendFlow() async throws {
        let connection = ScriptedConnection(script: [
            .read("220 smtp.example ready"),
            .write("EHLO vermail.local"),
            .read("250-smtp.example"), .read("250 AUTH PLAIN LOGIN"),
            .write("AUTH LOGIN"), .read("334 VXNlcm5hbWU6"),
            .write("dXNlcg==", sensitive: true), .read("334 UGFzc3dvcmQ6"),
            .write("cGFzcw==", sensitive: true), .read("235 2.7.0 Auth OK"),
            .write("MAIL FROM:<alice@example.com>"), .read("250 2.1.0 Ok"),
            .write("RCPT TO:<bob@example.com>"), .read("250 2.1.5 Ok"),
            .write("DATA"), .read("354 End data with <CRLF>.<CRLF>"),
            .writeRaw("Subject: Hi\r\n\r\n..dot\r\nline"),
            .writeRaw("\r\n.\r\n"), .read("250 2.0.0 queued"),
        ])

        let client = SMTPClient(connection: connection)
        try await client.authenticate(credentials: .init(username: "user", password: "pass"), method: .login)
        try await client.send(.init(
            from: "alice@example.com",
            recipients: ["bob@example.com"],
            data: Data("Subject: Hi\n\n.dot\nline".utf8)
        ))
        await connection.assertScriptExhausted()
    }

    @Test func startTLSUpgradeAndPlainAuth() async throws {
        let connection = ScriptedConnection(script: [
            .read("220 smtp.example ready"),
            .write("EHLO vermail.local"),
            .read("250-smtp.example"), .read("250 STARTTLS"),
            .write("STARTTLS"), .read("220 Ready to start TLS"), .startTLS,
            .write("EHLO vermail.local"),
            .read("250-smtp.example"), .read("250 AUTH PLAIN"),
            .write("AUTH PLAIN AHVzZXIAcGFzcw==", sensitive: true), .read("235 2.7.0 Auth OK"),
        ])

        let client = SMTPClient(connection: connection, useStartTLS: true)
        try await client.authenticate(credentials: .init(username: "user", password: "pass"), method: .plain)
        await connection.assertScriptExhausted()
    }

    @Test func unsupportedStartTLSThrows() async throws {
        let connection = ScriptedConnection(script: [
            .read("220 smtp.example ready"),
            .write("EHLO vermail.local"),
            .read("250 smtp.example"),
        ])
        let client = SMTPClient(connection: connection, useStartTLS: true)

        do {
            try await client.connect()
            #expect(Bool(false), "STARTTLS without capability must throw")
        } catch let error as SMTPError {
            if case .unsupportedAuthentication("STARTTLS") = error {
                #expect(Bool(true))
            } else {
                #expect(Bool(false), "Unexpected SMTPError: \(error)")
            }
        }
    }
}

enum SMTPTestStep: Sendable, Equatable {
    case read(String)
    case write(String, sensitive: Bool = false)
    case writeRaw(String)
    case startTLS
}

actor ScriptedConnection: MailConnection {
    private var script: [SMTPTestStep]

    init(script: [SMTPTestStep]) {
        self.script = script
    }

    func open() async throws(TransportError) {}

    func readLine() async throws(TransportError) -> Data {
        guard !script.isEmpty else { throw .connectionClosed }
        let step = script.removeFirst()
        guard case let .read(line) = step else {
            throw .connectionFailed("Expected \(step), got read")
        }
        return Data(line.utf8)
    }

    func write(_ data: Data, sensitive: Bool) async throws(TransportError) {
        guard !script.isEmpty else { throw .connectionClosed }
        let step = script.removeFirst()
        switch step {
        case let .write(expected, expectedSensitive):
            let actual = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
            if actual != expected || expectedSensitive != sensitive {
                let message =
                    "Expected write '\(expected)' sensitive=\(expectedSensitive), " +
                    "got '\(actual)' sensitive=\(sensitive)"
                throw .connectionFailed(
                    message
                )
            }
        case let .writeRaw(expectedRaw):
            let actual = String(decoding: data, as: UTF8.self)
            if actual != expectedRaw {
                throw .connectionFailed("Expected raw write '\(expectedRaw)', got '\(actual)'")
            }
        default:
            throw .connectionFailed("Expected \(step), got write")
        }
    }

    func startTLS() async throws(TransportError) {
        guard !script.isEmpty else { throw .connectionClosed }
        let step = script.removeFirst()
        guard step == .startTLS else {
            throw .connectionFailed("Expected \(step), got startTLS")
        }
    }

    func close() async {}

    func assertScriptExhausted() async {
        #expect(script.isEmpty, "Unconsumed script: \(script)")
    }
}

@Suite(.greenMail, .timeLimit(.minutes(1)))
struct SMTPGreenMailTests {
    @Test func sendMessageAndReadBackViaPOP3() async throws {
        let marker = UUID().uuidString

        let smtp = SMTPClient(configuration: .init(host: "localhost", port: 3025, security: .none, timeout: 5))
        defer { Task { await smtp.close() } }

        try await smtp.connect()
        try await smtp.send(.init(
            from: "alice@localhost",
            recipients: ["test@localhost"],
            data: Data("Subject: Vermail SMTP Test\r\n\r\nbody \(marker)".utf8)
        ))

        let pop3 = POP3Client(configuration: .init(host: "localhost", port: 3110, security: .none, timeout: 5))
        defer { Task { await pop3.close() } }

        try await pop3.authenticate(credentials: .init(username: "test@localhost", password: "test"))
        let refs = try await pop3.listMessages()
        var found = false
        for ref in refs.reversed().prefix(10) {
            let data = try await pop3.fetchMessage(ref)
            let text = String(decoding: data, as: UTF8.self)
            if text.contains(marker) {
                found = true
                break
            }
        }
        #expect(found)
    }
}
