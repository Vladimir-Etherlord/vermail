import Foundation
import GRDB
import MailCore
import Testing

func writeAirmail(at root: URL) throws {
    let account = root.appending(path: "ada@example.com_1", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
        at: account.appending(path: "Message", directoryHint: .isDirectory),
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: account.appending(path: "Body", directoryHint: .isDirectory),
        withIntermediateDirectories: true
    )
    try writeFolders(account.appending(path: "Data.db"))
    try writeMessages(account.appending(path: "Message/Message_0_1_50000.db"))
    try writeBodies(account.appending(path: "Body/Body_0_1_50000.db"))
    try writeRFC(account.appending(path: "Rfc.db"))
}

private func writeFolders(_ url: URL) throws {
    let queue = try DatabaseQueue(path: url.fileSystemPath)
    try queue.write { database in
        try database.execute(sql: """
        CREATE TABLE folders (
            idx INTEGER PRIMARY KEY,
            name TEXT,
            standardFolderid INTEGER
        )
        """)
        try database.execute(sql: "INSERT INTO folders (idx, name, standardFolderid) VALUES (1, 'Inbox', 1)")
        try database.execute(sql: "INSERT INTO folders (idx, name, standardFolderid) VALUES (2, 'Черновики', 3)")
        try database.execute(sql: "INSERT INTO folders (idx, name, standardFolderid) VALUES (3, 'Вся почта', 8)")
    }
}

private func writeMessages(_ url: URL) throws {
    let queue = try DatabaseQueue(path: url.fileSystemPath)
    try queue.write { database in
        try database.execute(sql: """
        CREATE TABLE messages (
            idx INTEGER PRIMARY KEY,
            messageid TEXT,
            subject TEXT,
            uidfolderid BLOB,
            senderaddr BLOB,
            senderdate INTEGER,
            rcvdate INTEGER,
            tox BLOB,
            ccx BLOB,
            bccx BLOB,
            attachmentscount INTEGER,
            excerpt TEXT,
            flagx INTEGER
        )
        """)
        try insertMessages(database)
    }
}

private func insertMessages(_ database: Database) throws {
    try insert(database, knownMessage())
    try insert(database, helloMessage())
    try insert(database, draftMessage())
    try insert(database, emptyMessage())
    try insert(database, fileMessage())
}

private func writeBodies(_ url: URL) throws {
    let queue = try DatabaseQueue(path: url.fileSystemPath)
    let gzip = try gzipText()
    try queue.write { database in
        try database.execute(sql: """
        CREATE TABLE bodies (
            idx INTEGER PRIMARY KEY,
            plainBody BLOB,
            htmlBody BLOB,
            ezip INTEGER
        )
        """)
        try database.execute(
            sql: "INSERT INTO bodies (idx, plainBody, htmlBody, ezip) VALUES (?, ?, NULL, 1)",
            arguments: [2, gzip]
        )
        try database.execute(
            sql: "INSERT INTO bodies (idx, plainBody, htmlBody, ezip) VALUES (3, 'draft body', NULL, 0)"
        )
        try database.execute(
            sql: "INSERT INTO bodies (idx, plainBody, htmlBody, ezip) VALUES (5, 'WRONG', NULL, 0)"
        )
    }
}

private func writeRFC(_ url: URL) throws {
    let queue = try DatabaseQueue(path: url.fileSystemPath)
    try queue.write { database in
        try database.execute(sql: "CREATE TABLE rfcdata (idx INTEGER PRIMARY KEY, rfc BLOB)")
        try database.execute(
            sql: "INSERT INTO rfcdata (idx, rfc) VALUES (?, ?)",
            arguments: [5, Data(fileRFC.utf8)]
        )
    }
}

private func gzipText() throws -> Data {
    let encoded = "H4sIAAAAAAAC/7sw/cKWiw0XNlzYdLHxYhOQbL6wE0hvBQBsH3TyGAAAAA=="
    return try #require(Data(base64Encoded: encoded))
}

private func insert(_ database: Database, _ message: AirmailFixtureMessage) throws {
    try database.execute(
        sql: """
        INSERT INTO messages (
            idx, messageid, subject, uidfolderid, senderaddr, senderdate, rcvdate,
            tox, ccx, bccx, attachmentscount, excerpt, flagx
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        arguments: [
            message.idx, message.messageID, message.subject, message.folder, message.sender,
            message.sentAt, message.receivedAt, message.to, message.cc, message.bcc,
            message.attachments, message.excerpt, message.flag,
        ]
    )
}

private struct AirmailFixtureMessage {
    var idx: Int64
    var messageID: String?
    var subject: String?
    var folder: Data
    var sender: Data
    var sentAt: Int64?
    var receivedAt: Int64?
    var to: Data
    var cc: Data = .init()
    var bcc: Data = .init()
    var attachments: Int
    var excerpt: String?
    var flag: Int64?

    init(
        idx: Int64,
        messageID: String? = nil,
        subject: String? = nil,
        folder: Data,
        sender: Data,
        sentAt: Int64? = nil,
        receivedAt: Int64? = nil,
        to: Data = Data(),
        cc: Data = Data(),
        bcc: Data = Data(),
        attachments: Int,
        excerpt: String? = nil,
        flag: Int64? = nil
    ) {
        self.idx = idx
        self.messageID = messageID
        self.subject = subject
        self.folder = folder
        self.sender = sender
        self.sentAt = sentAt
        self.receivedAt = receivedAt
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.attachments = attachments
        self.excerpt = excerpt
        self.flag = flag
    }
}

private func knownMessage() throws -> AirmailFixtureMessage {
    try AirmailFixtureMessage(
        idx: 1,
        messageID: "<Known@Example.com>",
        subject: "Old",
        folder: folderBlob([1: "uidl-known-message"]),
        sender: Data("ada@example.com".utf8),
        receivedAt: 1_700_000_000,
        to: Data("bob@example.com".utf8),
        attachments: 0,
        flag: 1
    )
}

private func helloMessage() throws -> AirmailFixtureMessage {
    var sender = Data([0xFF, 0x00])
    sender.append(Data("Ada <ada@example.com>".utf8))
    return try AirmailFixtureMessage(
        idx: 2,
        messageID: "<new@example.com>",
        subject: "Привет",
        folder: folderBlob([1: "uidl-179209330164", 3: "uidl-179209330164"]),
        sender: sender,
        receivedAt: 1_763_000_000,
        to: Data("bob@example.com".utf8),
        cc: Data("cara@example.com".utf8),
        attachments: 0,
        excerpt: "Hello there",
        flag: 1
    )
}

private func draftMessage() throws -> AirmailFixtureMessage {
    try AirmailFixtureMessage(
        idx: 3,
        subject: "Draft note",
        folder: folderBlob([2: "12"]),
        sender: Data("ada@example.com".utf8),
        to: Data(),
        attachments: 0,
        flag: 0
    )
}

private func emptyMessage() -> AirmailFixtureMessage {
    AirmailFixtureMessage(idx: 4, folder: Data(), sender: Data(), to: Data(), attachments: 0)
}

private func fileMessage() throws -> AirmailFixtureMessage {
    try AirmailFixtureMessage(
        idx: 5,
        subject: "File",
        folder: folderBlob([1: "uidl-file-message"]),
        sender: Data("ada@example.com".utf8),
        to: Data("bob@example.com".utf8),
        attachments: 1,
        flag: 1
    )
}

private func folderBlob(_ pairs: [Int: String]) throws -> Data {
    let map = NSMutableDictionary()
    for (id, uid) in pairs.sorted(by: { $0.key < $1.key }) {
        map.setObject(NSString(string: uid), forKey: NSNumber(value: id))
    }
    return try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: false)
}

private let fileRFC = """
From: ada@example.com
To: bob@example.com
Message-ID: <rfc@example.com>
Subject: File
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="bound"

--bound
Content-Type: text/plain; charset=utf-8

See file
--bound
Content-Type: text/plain; name="note.txt"
Content-Disposition: attachment; filename="note.txt"

hello
--bound--

"""
