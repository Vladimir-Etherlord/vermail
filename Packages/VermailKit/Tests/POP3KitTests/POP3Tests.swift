import Foundation
import MailCore
import MailTransport
import POP3Kit
import Testing

struct POP3Tests {
    @Test(arguments: [(ConnectionSecurity.none, 110), (.startTLS, 110), (.ssl, 995)])
    func defaultPort(security: ConnectionSecurity, port: Int) {
        #expect(POP3.defaultPort(for: security) == port)
    }

    @Test func listFetchDeleteMessages() async throws {
        let connection = ScriptedConnection(script: [
            .read("+OK hello <challenge@test>"),
            .write("USER user"), .read("+OK"),
            .write("PASS pass", sensitive: true), .read("+OK"),
            .write("UIDL"), .read("+OK"), .read("1 uid-a"), .read("2 uid-b"), .read("."),
            .write("LIST"), .read("+OK"), .read("1 4"), .read("2 9"), .read("."),
            .write("UIDL"), .read("+OK"), .read("1 uid-a"), .read("2 uid-b"), .read("."),
            .write("RETR 2"), .read("+OK"), .read("..starts with dot"), .read("line 2"), .read("."),
            .write("UIDL"), .read("+OK"), .read("1 uid-a"), .read("2 uid-b"), .read("."),
            .write("DELE 2"), .read("+OK"),
        ])
        let client = POP3Client(connection: connection)
        try await client.authenticate(credentials: .init(username: "user", password: "pass"))

        let refs = try await client.listMessages()
        #expect(refs.count == 2)
        #expect(refs.contains { $0.uid == "uid-b" && $0.size == 9 })

        let message = try await client.fetchMessage(.init(uid: "uid-b", size: 9))
        #expect(String(decoding: message, as: UTF8.self).hasPrefix(".starts with dot\r\nline 2\r\n"))

        try await client.deleteMessages([.init(uid: "uid-b", size: 9)])
        await connection.assertScriptExhausted()
    }

    @Test func startTLSIsRequestedOnce() async throws {
        let connection = ScriptedConnection(script: [
            .read("+OK ready"),
            .write("STLS"), .read("+OK begin TLS"), .startTLS,
            .write("USER user"), .read("+OK"),
            .write("PASS pass", sensitive: true), .read("+OK"),
        ])
        let client = POP3Client(connection: connection, useStartTLS: true)
        try await client.authenticate(credentials: .init(username: "user", password: "pass"))
        await connection.assertScriptExhausted()
    }

    @Test func authLoginSendsBase64Chunks() async throws {
        let connection = ScriptedConnection(script: [
            .read("+OK ready"),
            .write("AUTH LOGIN"), .read("+ VXNlcm5hbWU6"),
            .write("dXNlcg==", sensitive: true), .read("+ UGFzc3dvcmQ6"),
            .write("cGFzcw==", sensitive: true), .read("+OK auth"),
        ])
        let client = POP3Client(connection: connection)
        try await client.authenticate(credentials: .init(username: "user", password: "pass"), method: .login)
        await connection.assertScriptExhausted()
    }

    @Test func authPlainFormatsPayload() async throws {
        let connection = ScriptedConnection(script: [
            .read("+OK ready"),
            .write("AUTH PLAIN AHVzZXIAcGFzcw==", sensitive: true), .read("+OK"),
        ])
        let client = POP3Client(connection: connection)
        try await client.authenticate(credentials: .init(username: "user", password: "pass"), method: .plain)
        await connection.assertScriptExhausted()
    }

    @Test func authXOAUTH2FormatsPayload() async throws {
        let connection = ScriptedConnection(script: [
            .read("+OK ready"),
            .write("AUTH XOAUTH2 dXNlcj11c2VyQGV4YW1wbGUuY29tAWF1dGg9QmVhcmVyIHRva2VuMTIzAQE=", sensitive: true),
            .read("+OK"),
        ])
        let client = POP3Client(connection: connection)
        try await client.authenticate(
            credentials: .init(username: "user@example.com", oauthBearerToken: "token123"),
            method: .xoauth2
        )
        await connection.assertScriptExhausted()
    }

    @Test func authAPOPUsesGreetingChallenge() async throws {
        let connection = ScriptedConnection(script: [
            .read("+OK server <12345@mail.example>"),
            .write("APOP user faf0189b4e27c18fdcfedb5cefb6a024", sensitive: true), .read("+OK"),
        ])
        let client = POP3Client(connection: connection)
        try await client.authenticate(credentials: .init(username: "user", password: "pass"), method: .apop)
        await connection.assertScriptExhausted()
    }

    @Test func authCRAMMD5UsesChallenge() async throws {
        let challenge = Data("challenge".utf8).base64EncodedString()
        let connection = ScriptedConnection(script: [
            .read("+OK server"),
            .write("AUTH CRAM-MD5"), .read("+ \(challenge)"),
            .write("dXNlciAyNzBhZjljNzIzNGI3YzAzYjBkNTQ5MDM2MGQ4Y2FkOA==", sensitive: true), .read("+OK"),
        ])
        let client = POP3Client(connection: connection)
        try await client.authenticate(credentials: .init(username: "user", password: "pass"), method: .cramMD5)
        await connection.assertScriptExhausted()
    }
}

enum ScriptStep: Sendable, Equatable {
    case read(String)
    case write(String, sensitive: Bool = false)
    case startTLS
}

actor ScriptedConnection: MailConnection {
    private var script: [ScriptStep]

    init(script: [ScriptStep]) {
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
        guard case let .write(expected, expectedSensitive) = step else {
            throw .connectionFailed("Expected \(step), got write")
        }
        let actual = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
        if actual != expected || expectedSensitive != sensitive {
            throw .connectionFailed(
                "Expected write '\(expected)' sensitive=\(expectedSensitive), got '\(actual)' sensitive=\(sensitive)"
            )
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
struct POP3GreenMailTests {
    @Test func authenticateListAndFetchOnGreenMail() async throws {
        let client = POP3Client(configuration: .init(host: "localhost", port: 3110, security: .none, timeout: 5))
        defer { Task { await client.close() } }

        try await client.authenticate(credentials: .init(username: "test@localhost", password: "test"))
        let capabilities = try await client.capabilities()
        #expect(capabilities.contains(where: { $0.contains("UIDL") }))

        let refs = try await client.listMessages()
        if let first = refs.first {
            let message = try await client.fetchMessage(first)
            #expect(!message.isEmpty)
        }
    }
}
