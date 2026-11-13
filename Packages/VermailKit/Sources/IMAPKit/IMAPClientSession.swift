import CryptoKit
import Foundation
import MailCore
import MailTransport

extension IMAPClient {
    func upgradeToTLS() async throws {
        try await loadCapabilities()
        guard capabilities.contains("STARTTLS") else { throw IMAPError.startTLSUnavailable }
        _ = try await send("STARTTLS")
        try await connection.startTLS()
        didLoadCapabilities = false
        capabilities = []
    }

    func ensureAuthenticated() async throws {
        try await connect()
        if !isAuthenticated {
            throw IMAPError.notAuthenticated
        }
    }

    func login(_ credentials: IMAPCredentials) async throws {
        guard let password = credentials.password else { throw IMAPError.missingPassword }
        let safe = IMAPParser.isQuotedSafe(credentials.username) && IMAPParser.isQuotedSafe(password)
        if !safe {
            try await authenticatePlain(credentials)
            return
        }
        let user = IMAPParser.quote(credentials.username)
        let secret = IMAPParser.quote(password)
        _ = try await send("LOGIN \(user) \(secret)", sensitive: true)
    }

    func authenticatePlain(_ credentials: IMAPCredentials) async throws {
        guard let password = credentials.password else { throw IMAPError.missingPassword }
        let tag = makeTag()
        try await connection.writeLine("\(tag) AUTHENTICATE PLAIN")
        _ = try await readContinuation(tag: tag)
        let raw = "\u{0}\(credentials.username)\u{0}\(password)"
        try await connection.writeLine(Data(raw.utf8).base64EncodedString(), sensitive: true)
        _ = try await readReply(tag: tag)
    }

    func authenticateSASLLogin(_ credentials: IMAPCredentials) async throws {
        guard let password = credentials.password else { throw IMAPError.missingPassword }
        let tag = makeTag()
        try await connection.writeLine("\(tag) AUTHENTICATE LOGIN")
        _ = try await readContinuation(tag: tag)
        let user = Data(credentials.username.utf8).base64EncodedString()
        try await connection.writeLine(user, sensitive: true)
        _ = try await readContinuation(tag: tag)
        try await connection.writeLine(Data(password.utf8).base64EncodedString(), sensitive: true)
        _ = try await readReply(tag: tag)
    }

    func authenticateCRAMMD5(_ credentials: IMAPCredentials) async throws {
        guard let password = credentials.password else { throw IMAPError.missingPassword }
        let tag = makeTag()
        try await connection.writeLine("\(tag) AUTHENTICATE CRAM-MD5")
        let challengeText = try await readContinuation(tag: tag)
        guard let challenge = Data(base64Encoded: challengeText) else {
            throw IMAPError.invalidResponse(challengeText)
        }
        let digest = HMAC<Insecure.MD5>.authenticationCode(
            for: challenge,
            using: SymmetricKey(data: Data(password.utf8))
        )
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let payload = Data("\(credentials.username) \(hex)".utf8).base64EncodedString()
        try await connection.writeLine(payload, sensitive: true)
        _ = try await readReply(tag: tag)
    }

    func authenticateXOAUTH2(_ credentials: IMAPCredentials) async throws {
        guard let token = credentials.oauthBearerToken else { throw IMAPError.missingOAuthToken }
        let tag = makeTag()
        try await connection.writeLine("\(tag) AUTHENTICATE XOAUTH2")
        _ = try await readContinuation(tag: tag)
        let payload = OAuthConfigurationCatalog.xoauth2Payload(
            emailAddress: credentials.username,
            accessToken: token
        )
        try await connection.writeLine(payload, sensitive: true)
        _ = try await readReply(tag: tag)
    }

    func loadCapabilities() async throws {
        if didLoadCapabilities {
            return
        }
        let reply = try await send("CAPABILITY")
        let text = reply.lines.map(\.text).joined(separator: " ")
        capabilities = Set(text.uppercased().split(separator: " ").map(String.init))
        didLoadCapabilities = true
    }

    func select(rawName: String) async throws {
        let name = IMAPParser.canonicalMailbox(rawName)
        if selectedName == name {
            return
        }
        let reply = try await send("SELECT \(IMAPParser.quote(name))")
        let texts = reply.lines.map(\.text) + [reply.statusText]
        selectedName = name
        uidValidity = texts.compactMap { IMAPParser.uidValidity(in: $0) }.first ?? "0"
    }

    func messageRefs(from reply: IMAPReply) -> [RemoteMessageRef] {
        let mailbox = selectedName ?? "INBOX"
        return IMAPParser.fetchRecords(from: reply.lines).map { record in
            let key = IMAPMessageKey(mailbox: mailbox, uidValidity: uidValidity, uid: record.uid)
            return RemoteMessageRef(uid: key.storageValue, size: record.size, isRead: record.isRead)
        }
    }

    func delete(_ refs: [RemoteMessageRef], mailbox: String) async throws {
        guard let first = refs.first else { return }
        guard !mailbox.isEmpty else { throw IMAPError.messageNotFound(first.uid) }
        let uids = try refs.map { ref -> String in
            guard let uid = IMAPMessageKey.parse(ref.uid)?.uid else {
                throw IMAPError.messageNotFound(ref.uid)
            }
            return uid
        }
        try await select(rawName: mailbox)
        try await expunge(uids)
    }

    func expunge(_ uids: [String]) async throws {
        var start = 0
        while start < uids.count {
            let end = min(start + 50, uids.count)
            let set = uids[start ..< end].joined(separator: ",")
            _ = try await send("UID STORE \(set) +FLAGS.SILENT (\\Deleted)")
            if capabilities.contains("UIDPLUS") {
                _ = try await send("UID EXPUNGE \(set)")
            } else {
                _ = try await send("EXPUNGE")
            }
            start = end
        }
    }

    func send(_ text: String, sensitive: Bool = false) async throws -> IMAPReply {
        let tag = makeTag()
        try await connection.writeLine("\(tag) \(text)", sensitive: sensitive)
        return try await readReply(tag: tag)
    }

    func makeTag() -> String {
        tagNumber += 1
        return String(format: "A%03d", tagNumber)
    }

    func readReply(tag: String) async throws -> IMAPReply {
        var lines: [IMAPLine] = []
        while true {
            let line = try await readChunk()
            if let status = taggedStatus(line.text, tag: tag) {
                guard status == "OK" else { throw IMAPError.serverError(line.text) }
                return IMAPReply(lines: lines, statusText: line.text)
            }
            if line.text.uppercased().hasPrefix("* BYE") {
                throw IMAPError.serverError(line.text)
            }
            lines.append(line)
        }
    }

    func readContinuation(tag: String) async throws -> String {
        let line = try await connection.readLineString()
        if line.hasPrefix(tag + " ") {
            throw IMAPError.serverError(line)
        }
        guard line.hasPrefix("+") else { throw IMAPError.invalidResponse(line) }
        return line.dropFirst().trimmingCharacters(in: .whitespaces)
    }

    func readChunk() async throws -> IMAPLine {
        let text = try await connection.readLineString()
        guard let length = IMAPParser.literalLength(atEndOf: text) else {
            return IMAPLine(text: text, literal: nil)
        }
        guard length <= 64 * 1024 * 1024 else { throw IMAPError.invalidResponse(text) }
        let literal = try await connection.read(count: length)
        let trailer = try await connection.readLineString()
        guard let open = text.lastIndex(of: "{") else {
            return IMAPLine(text: text + trailer, literal: literal)
        }
        let prefix = text[..<open].trimmingCharacters(in: .whitespaces)
        return IMAPLine(text: prefix + trailer, literal: literal)
    }

    func taggedStatus(_ line: String, tag: String) -> String? {
        let prefix = tag + " "
        guard line.hasPrefix(prefix) else { return nil }
        let rest = line.dropFirst(prefix.count)
        for token in ["OK", "NO", "BAD"] where rest.hasPrefix(token) {
            return token
        }
        return nil
    }
}
