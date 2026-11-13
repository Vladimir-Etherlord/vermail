import Foundation
import MailCore
import MailTransport
import Testing
@testable import IMAPKit

struct IMAPTests {
    @Test(arguments: [(ConnectionSecurity.none, 143), (.startTLS, 143), (.ssl, 993)])
    func defaultPort(security: ConnectionSecurity, port: Int) {
        #expect(IMAP.defaultPort(for: security) == port)
    }

    @Test func modifiedUTF7RoundTripAndKnownMailbox() {
        #expect(IMAPUTF7.encode("INBOX") == "INBOX")
        #expect(IMAPUTF7.encode("a&b") == "a&-b")
        #expect(IMAPUTF7.decode("&-") == "&")
        #expect(IMAPUTF7.decode(IMAPUTF7.encode("Отправленные")) == "Отправленные")
        #expect(IMAPUTF7.decode("~peter/mail/&U,BTFw-/&ZeVnLIqe-") == "~peter/mail/台北/日本語")
        let encoded = IMAPUTF7.encode("Отправленные")
        #expect(IMAPParser.mailboxFolder(attributes: [], rawName: encoded) == .sent)
        #expect(IMAPParser.mailboxFolder(attributes: ["\\Sent"], rawName: "Whatever") == .sent)
        #expect(IMAPParser.mailboxFolder(attributes: ["\\Noselect"], rawName: "Sent") == nil)
        #expect(IMAPParser.mailboxFolder(attributes: ["\\All"], rawName: "All Mail") == nil)
    }

    @Test func loginListsMailboxAndFetchesLiteral() async throws {
        let connection = ScriptedConnection(script: [
            .read("* OK ready"),
            .write("A001 LOGIN \"user\" \"pass\"", sensitive: true), .read("A001 OK"),
            .write("A002 LIST \"\" \"*\""),
            .read("* LIST (\\HasNoChildren) \"/\" INBOX"),
            .read("* LIST (\\Sent) \"/\" Sent"),
            .read("A002 OK"),
            .write("A003 SELECT \"Sent\""),
            .read("* OK [UIDVALIDITY 3] UIDs valid"),
            .read("A003 OK [READ-WRITE] SELECT"),
            .write("A004 UID FETCH 1:* (UID RFC822.SIZE FLAGS)"),
            .read("* 1 FETCH (UID 8 RFC822.SIZE 5 FLAGS (\\Seen))"),
            .read("A004 OK"),
            .write("A005 UID FETCH 8 (BODY.PEEK[])"),
            .read("* 1 FETCH (UID 8 BODY[] {5}"),
            .readBytes("hello"),
            .read(")"),
            .read("A005 OK"),
        ])
        let client = IMAPClient(connection: connection)
        try await client.authenticate(credentials: .init(username: "user", password: "pass"))
        let boxes = try await client.remoteMailboxes()
        #expect(boxes.map(\.folder) == [.inbox, .sent])
        try await client.selectMailbox(boxes[1])
        let refs = try await client.listMessages()
        #expect(refs.count == 1)
        #expect(refs[0].uid == "Sent\u{1}3\u{1}8")
        #expect(refs[0].size == 5)
        #expect(refs[0].isRead)
        let body = try await client.fetchMessage(refs[0])
        #expect(body == Data("hello".utf8))
        await connection.assertScriptExhausted()
    }

    @Test func plainCramAndXOAuth2() async throws {
        let plain = ScriptedConnection(script: [
            .read("* OK"),
            .write("A001 AUTHENTICATE PLAIN"), .read("+"),
            .write("AHVzZXIAcGFzcw==", sensitive: true), .read("A001 OK"),
        ])
        let plainClient = IMAPClient(connection: plain)
        try await plainClient.authenticate(credentials: .init(username: "user", password: "pass"), method: .plain)

        let challenge = Data("challenge".utf8).base64EncodedString()
        let cram = ScriptedConnection(script: [
            .read("* OK"),
            .write("A001 AUTHENTICATE CRAM-MD5"), .read("+ \(challenge)"),
            .write("dXNlciAyNzBhZjljNzIzNGI3YzAzYjBkNTQ5MDM2MGQ4Y2FkOA==", sensitive: true),
            .read("A001 OK"),
        ])
        let cramClient = IMAPClient(connection: cram)
        try await cramClient.authenticate(credentials: .init(username: "user", password: "pass"), method: .cramMD5)

        let token = OAuthConfigurationCatalog.xoauth2Payload(emailAddress: "user@example.com", accessToken: "token123")
        let oauth = ScriptedConnection(script: [
            .read("* OK"),
            .write("A001 AUTHENTICATE XOAUTH2"), .read("+"),
            .write(token, sensitive: true), .read("A001 OK"),
        ])
        let oauthClient = IMAPClient(connection: oauth)
        try await oauthClient.authenticate(
            credentials: .init(username: "user@example.com", oauthBearerToken: "token123"),
            method: .xoauth2
        )
        await plain.assertScriptExhausted()
        await cram.assertScriptExhausted()
        await oauth.assertScriptExhausted()
    }

    @Test func saslLoginAndStartTLS() async throws {
        let login = ScriptedConnection(script: [
            .read("* OK"),
            .write("A001 AUTHENTICATE LOGIN"), .read("+ VXNlcm5hbWU6"),
            .write("dXNlcg==", sensitive: true), .read("+ UGFzc3dvcmQ6"),
            .write("cGFzcw==", sensitive: true), .read("A001 OK"),
        ])
        let loginClient = IMAPClient(connection: login)
        try await loginClient.authenticate(credentials: .init(username: "user", password: "pass"), method: .saslLogin)

        let tls = ScriptedConnection(script: [
            .read("* OK"),
            .write("A001 CAPABILITY"),
            .read("* CAPABILITY IMAP4rev1 STARTTLS AUTH=PLAIN"),
            .read("A001 OK"),
            .write("A002 STARTTLS"), .read("A002 OK"),
            .startTLS,
            .write("A003 LOGIN \"user\" \"pass\"", sensitive: true), .read("A003 OK"),
        ])
        let tlsClient = IMAPClient(connection: tls, useStartTLS: true)
        try await tlsClient.authenticate(credentials: .init(username: "user", password: "pass"))
        await login.assertScriptExhausted()
        await tls.assertScriptExhausted()
    }

    @Test func deleteUsesUIDPlusWhenAdvertised() async throws {
        let connection = ScriptedConnection(script: [
            .read("* OK"),
            .write("A001 LOGIN \"user\" \"pass\"", sensitive: true), .read("A001 OK"),
            .write("A002 CAPABILITY"),
            .read("* CAPABILITY IMAP4rev1 UIDPLUS"),
            .read("A002 OK"),
            .write("A003 SELECT \"INBOX\""),
            .read("* OK [UIDVALIDITY 1]"),
            .read("A003 OK"),
            .write("A004 UID STORE 8 +FLAGS.SILENT (\\Deleted)"), .read("A004 OK"),
            .write("A005 UID EXPUNGE 8"), .read("A005 OK"),
        ])
        let client = IMAPClient(connection: connection)
        try await client.authenticate(credentials: .init(username: "user", password: "pass"))
        try await client.deleteMessages([RemoteMessageRef(uid: "INBOX\u{1}1\u{1}8", size: 5)])
        await connection.assertScriptExhausted()
    }

    @Test func deleteFallsBackToExpunge() async throws {
        let connection = ScriptedConnection(script: [
            .read("* OK"),
            .write("A001 LOGIN \"user\" \"pass\"", sensitive: true), .read("A001 OK"),
            .write("A002 CAPABILITY"),
            .read("* CAPABILITY IMAP4rev1"),
            .read("A002 OK"),
            .write("A003 SELECT \"INBOX\""),
            .read("* OK [UIDVALIDITY 1]"),
            .read("A003 OK"),
            .write("A004 UID STORE 8 +FLAGS.SILENT (\\Deleted)"), .read("A004 OK"),
            .write("A005 EXPUNGE"), .read("A005 OK"),
        ])
        let client = IMAPClient(connection: connection)
        try await client.authenticate(credentials: .init(username: "user", password: "pass"))
        try await client.deleteMessages([RemoteMessageRef(uid: "INBOX\u{1}1\u{1}8", size: 5)])
        await connection.assertScriptExhausted()
    }

    @Test func copyUIDExpandsRanges() {
        let parsed = IMAPParser.copyUID(in: "A004 OK [COPYUID 4 8,10:11 21,22:23] Done")
        #expect(parsed?.uidValidity == "4")
        #expect(parsed?.source == ["8", "10", "11"])
        #expect(parsed?.destination == ["21", "22", "23"])
    }

    @Test func setReadStoresTheSeenFlag() async throws {
        let connection = ScriptedConnection(script: [
            .read("* OK"),
            .write("A001 LOGIN \"user\" \"pass\"", sensitive: true), .read("A001 OK"),
            .write("A002 SELECT \"INBOX\""),
            .read("* OK [UIDVALIDITY 1]"),
            .read("A002 OK"),
            .write("A003 UID STORE 8 +FLAGS.SILENT (\\Seen)"), .read("A003 OK"),
            .write("A004 UID STORE 8 -FLAGS.SILENT (\\Seen)"), .read("A004 OK"),
        ])
        let client = IMAPClient(connection: connection)
        let ref = RemoteMessageRef(uid: "INBOX\u{1}1\u{1}8", size: 5)
        try await client.authenticate(credentials: .init(username: "user", password: "pass"))
        try await client.setRead(true, refs: [ref])
        try await client.setRead(false, refs: [ref])
        await connection.assertScriptExhausted()
    }

    @Test func moveUsesUIDMoveAndRemembersTheNewKey() async throws {
        let connection = ScriptedConnection(script: [
            .read("* OK"),
            .write("A001 LOGIN \"user\" \"pass\"", sensitive: true), .read("A001 OK"),
            .write("A002 CAPABILITY"),
            .read("* CAPABILITY IMAP4rev1 MOVE UIDPLUS"),
            .read("A002 OK"),
            .write("A003 SELECT \"INBOX\""),
            .read("* OK [UIDVALIDITY 1]"),
            .read("A003 OK"),
            .write("A004 UID MOVE 8 \"Trash\""),
            .read("A004 OK [COPYUID 4 8 21]"),
        ])
        let client = IMAPClient(connection: connection)
        try await client.authenticate(credentials: .init(username: "user", password: "pass"))
        let moved = try await client.moveMessages(
            [RemoteMessageRef(uid: "INBOX\u{1}1\u{1}8", size: 5)],
            to: RemoteMailbox(name: "Trash", folder: .trash)
        )
        #expect(moved.map(\.destinationUID) == ["Trash\u{1}4\u{1}21"])
        await connection.assertScriptExhausted()
    }

    @Test func moveCopiesThenExpungesWhenMoveIsUnavailable() async throws {
        let connection = ScriptedConnection(script: [
            .read("* OK"),
            .write("A001 LOGIN \"user\" \"pass\"", sensitive: true), .read("A001 OK"),
            .write("A002 CAPABILITY"),
            .read("* CAPABILITY IMAP4rev1 UIDPLUS"),
            .read("A002 OK"),
            .write("A003 SELECT \"INBOX\""),
            .read("* OK [UIDVALIDITY 1]"),
            .read("A003 OK"),
            .write("A004 UID COPY 8 \"Trash\""),
            .read("A004 OK [COPYUID 4 8 21]"),
            .write("A005 UID STORE 8 +FLAGS.SILENT (\\Deleted)"), .read("A005 OK"),
            .write("A006 UID EXPUNGE 8"), .read("A006 OK"),
        ])
        let client = IMAPClient(connection: connection)
        try await client.authenticate(credentials: .init(username: "user", password: "pass"))
        let moved = try await client.moveMessages(
            [RemoteMessageRef(uid: "INBOX\u{1}1\u{1}8", size: 5)],
            to: RemoteMailbox(name: "Trash", folder: .trash)
        )
        #expect(moved.map(\.destinationUID) == ["Trash\u{1}4\u{1}21"])
        await connection.assertScriptExhausted()
    }
}

enum ScriptStep: Sendable, Equatable {
    case read(String)
    case readBytes(String)
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

    func read(count: Int) async throws(TransportError) -> Data {
        guard !script.isEmpty else { throw .connectionClosed }
        let step = script.removeFirst()
        guard case let .readBytes(text) = step else {
            throw .connectionFailed("Expected \(step), got read(\(count))")
        }
        let data = Data(text.utf8)
        guard data.count == count else {
            throw .connectionFailed("Expected \(count) bytes, script has \(data.count)")
        }
        return data
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
