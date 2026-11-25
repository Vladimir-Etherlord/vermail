import Foundation
import MailCore
import MIMEKit
import Testing
@testable import AirmailImport

struct AirmailDecodingTests {
    @Test func folderChoicePrefersRealMailboxOverVirtual() {
        #expect(AirmailFolders.choose(names: ["Вся почта", "Входящие"]) == .inbox)
        #expect(AirmailFolders.choose(names: ["Корзина", "Inbox"]) == .trash)
        #expect(AirmailFolders.choose(names: ["Черновики"]) == .drafts)
        #expect(AirmailFolders.choose(names: ["Spam", "Archive"]) == .spam)
        #expect(AirmailFolders.choose(names: ["[Airmail]"]) == .inbox)
        #expect(AirmailFolders.choose(names: ["Projects"]) == .archive)
        #expect(AirmailFolders.kind(named: "Отправленные") == .sent)
    }

    @Test func datesAcceptUnixAndAppleEpochs() {
        let unix = Date(timeIntervalSince1970: 1_763_000_000)
        #expect(AirmailDates.date(from: 1_763_000_000) == unix)
        #expect(AirmailDates.date(from: 1_763_000_000_000) == unix)
        let year2002 = Date(timeIntervalSince1970: 1_029_737_595)
        #expect(AirmailDates.date(from: 1_029_737_595) == year2002)
        let apple = Date(timeIntervalSinceReferenceDate: 800_000_000)
        #expect(AirmailDates.date(from: 800_000_000) == apple)
        #expect(AirmailDates.date(from: 0) == nil)
    }

    @Test func missingFlagStaysReadAndSeenBitMarksRead() {
        #expect(AirmailFlags.isRead(nil))
        #expect(!AirmailFlags.isRead(0))
        #expect(AirmailFlags.isRead(1))
        #expect(AirmailFlags.isRead(5))
        #expect(!AirmailFlags.isRead(4))
    }

    @Test func addressesSurviveBinaryBlobs() {
        var blob = Data([0xFF, 0x00])
        blob.append(Data("Ada Lovelace <ada@example.com>".utf8))
        blob.append(Data(" and bob@example.com".utf8))
        #expect(AirmailAddresses.display(from: blob) == "Ada Lovelace <ada@example.com>")
        #expect(AirmailAddresses.emails(in: blob) == ["ada@example.com", "bob@example.com"])
    }

    @Test func messageIDIsNormalizedFromTheHeader() {
        let raw = Data("From: a@example.com\r\nMessage-ID: <AbC@Example.com>\r\n\r\nHi".utf8)
        #expect(AirmailMessageID.normalize("<AbC@Example.com>") == "abc@example.com")
        #expect(AirmailMessageID.headerValue(in: raw) == "abc@example.com")
        #expect(AirmailMessageID.remoteUID(shard: "Message_0_1_50000", idx: 2) == "airmail:Message_0_1_50000:2")
    }

    @Test func gzipBodyDecodesToText() throws {
        let encoded = "H4sIAAAAAAAC/7sw/cKWiw0XNlzYdLHxYhOQbL6wE0hvBQBsH3TyGAAAAA=="
        let data = try #require(Data(base64Encoded: encoded))
        #expect(AirmailCompression.text(from: data, compressed: true) == "Здравствуйте")
    }

    @Test func base64GzipTextDecodesToText() {
        let encoded = "H4sIAAAAAAAC/7sw/cKWiw0XNlzYdLHxYhOQbL6wE0hvBQBsH3TyGAAAAA=="
        #expect(AirmailCompression.text(from: Data(encoded.utf8), compressed: true) == "Здравствуйте")
    }

    @Test func attachmentArchiveReadsTheFileNextToTheMessage() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "vermail-attach-\(UUID().uuidString)")
        let folder = root.appending(path: "msg-1", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = folder.appending(path: "note.txt")
        try Data("hello-file".utf8).write(to: file)
        let archive = try attachmentArchive(
            fileName: "note.txt",
            path: "/old/AttachmentsNg/msg-1/note.txt",
            byteCount: 10
        )
        let files = AirmailAttachments.files(
            messageID: "msg-1",
            external: archive,
            inline: Data(),
            directory: root
        )
        #expect(files.count == 1)
        #expect(files.first?.filename == "note.txt")
        #expect(files.first?.data == Data("hello-file".utf8))
        let parsed = try MIME.parse(AirmailRFC.message(
            plain: "See file",
            html: "<p>See file</p>",
            headers: AirmailRFCHeaders(
                idx: 9,
                date: Date(timeIntervalSince1970: 1_700_000_000),
                from: "ada@example.com",
                to: ["bob@example.com"],
                cc: [],
                messageID: "attach@example.com",
                subject: "File"
            ),
            files: files
        ))
        #expect(parsed.plainBody == "See file")
        #expect(parsed.htmlBody == "<p>See file</p>")
        #expect(parsed.attachments.count == 1)
        #expect(parsed.attachments.first?.filename == "note.txt")
        #expect(parsed.attachments.first?.data == Data("hello-file".utf8))
    }

    @Test func htmlStoredAsPlainBecomesHTML() {
        let document = "<html><body>Hello</body></html>"
        let parts = AirmailBodyText.rendered(plain: document, html: "")
        #expect(parts.plain.isEmpty)
        #expect(parts.html == document)
        let duplicate = AirmailBodyText.rendered(plain: document, html: document)
        #expect(duplicate.plain.isEmpty)
        #expect(duplicate.html == document)
    }

    @Test func keyedArchiveKeepsFolderIDAndServerUID() throws {
        let map = NSMutableDictionary()
        map.setObject(NSString(string: "uidl-179209330164"), forKey: NSNumber(value: 7))
        let archived = try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: false)
        let binding = AirmailFolderBlob.binding(from: archived)
        #expect(binding.folderIDs == [7])
        #expect(binding.serverUID == "uidl-179209330164")

        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["3": "12"],
            format: .binary,
            options: 0
        )
        let short = AirmailFolderBlob.binding(from: plist)
        #expect(short.folderIDs == [3])
        #expect(short.serverUID == nil)
    }

    @Test func uidFlagsArchiveKeepsFolderAndSeenBit() throws {
        let seen = try uidFlagsArchive(folderID: 20, flags: 2)
        let seenBinding = AirmailFolderBlob.binding(from: seen)
        #expect(seenBinding.folderIDs == [20])
        #expect(seenBinding.isRead == true)

        let unread = try uidFlagsArchive(folderID: 19, flags: 0)
        #expect(AirmailFolderBlob.binding(from: unread).isRead == false)
        let stored = try #require(Data(base64Encoded: airmailFolderBlob))
        let binding = AirmailFolderBlob.binding(from: stored)
        #expect(binding.folderIDs == [16])
        #expect(binding.isRead == true)
    }

    @Test func unreadableLibraryExplainsFullDiskAccess() {
        let error = AirmailImportError.unreadableLibrary("/Airmail")
        #expect(error.description.contains("Full Disk Access"))
    }

    @Test func accountDirectoryStripsNumericSuffix() {
        let url = URL(fileURLWithPath: "/Airmail/ada@example.com_1", isDirectory: true)
        #expect(AirmailLocations.email(fromAccountDirectory: url) == "ada@example.com")
        #expect(AirmailLocations.sameEmail("Ada@Example.com", "ada@example.com"))
    }
}

private let airmailFolderBlob = """
YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05T\
S2V5ZWRBcmNoaXZlctEICVRyb290gAGmCwwVFhwiVSRudWxs0w0ODxASFFdOUy5rZXlzWk5TLm9iamVj\
dHNWJGNsYXNzoRGAAqETgAOABRAQ0xcYDxkaG1N1aWRVZmxhZ3MQARACgATSHR4fIFokY2xhc3NuYW1l\
WCRjbGFzc2VzWFVpZEZsYWdzoh8hWE5TT2JqZWN00h0eIyRfEBNOU011dGFibGVEaWN0aW9uYXJ5oyMl\
IVxOU0RpY3Rpb25hcnkIERokKTI3SUxRU1pgZ296gYOFh4mLjZSYnqCipKm0vcbJ0tft8QAAAAAAAAEB\
AAAAAAAAACYAAAAAAAAAAAAAAAAAAAD+
"""

private func attachmentArchive(fileName: String, path: String, byteCount: Int) throws -> Data {
    let objects: [Any] = [
        "$null",
        [
            "NS.objects": [["CF$UID": 2]],
            "$class": ["CF$UID": 3],
        ],
        [
            "fileName": ["CF$UID": 4],
            "path": ["CF$UID": 5],
            "size": byteCount,
            "contentype": ["CF$UID": 6],
            "internalx": 0,
            "$class": ["CF$UID": 3],
        ],
        ["$classname": "NSMutableArray", "$classes": ["NSMutableArray", "NSArray", "NSObject"]],
        fileName,
        path,
        "text/plain",
    ]
    let archive: [String: Any] = [
        "$version": 100_000,
        "$archiver": "NSKeyedArchiver",
        "$top": ["root": ["CF$UID": 1]],
        "$objects": objects,
    ]
    return try PropertyListSerialization.data(fromPropertyList: archive, format: .binary, options: 0)
}

private func uidFlagsArchive(folderID: Int, flags: Int) throws -> Data {
    let objects: [Any] = [
        "$null",
        [
            "NS.keys": [["CF$UID": 2]],
            "NS.objects": [["CF$UID": 3]],
            "$class": ["CF$UID": 5],
        ],
        folderID,
        ["uid": 1, "flags": flags, "$class": ["CF$UID": 4]],
        ["$classname": "UidFlags", "$classes": ["UidFlags", "NSObject"]],
        ["$classname": "NSDictionary", "$classes": ["NSDictionary", "NSObject"]],
    ]
    let archive: [String: Any] = [
        "$version": 100_000,
        "$archiver": "NSKeyedArchiver",
        "$top": ["root": ["CF$UID": 1]],
        "$objects": objects,
    ]
    return try PropertyListSerialization.data(fromPropertyList: archive, format: .binary, options: 0)
}
