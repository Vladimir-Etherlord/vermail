import Foundation
import MailCore

struct AirmailLetter: Sendable {
    var accountEmail: String
    var remoteUID: String
    var serverUID: String?
    var messageID: String?
    var subject: String
    var fromAddress: String
    var toAddresses: [String]
    var carbonCopy: [String]
    var blindCarbonCopy: [String]
    var receivedAt: Date?
    var isRead: Bool
    var folder: MailFolderKind
    var snippet: String?
    var hasAttachments: Bool
    var rawSource: Data
    var isEmpty: Bool
}

enum AirmailLetterBuilder {
    static func make(
        record: AirmailMessageRecord,
        body: AirmailBodyText,
        storedRFC: Data?,
        context: AirmailLetterContext
    ) -> AirmailLetter {
        let binding = AirmailFolderBlob.binding(from: record.folderBlob)
        let names = binding.folderIDs.compactMap { context.folders[$0] }
        let subject = AirmailRFC.readable(record.subject)
        let plain = body.plain
        let html = body.html
        let original = AirmailRFC.mailSource(from: storedRFC) ?? AirmailRFC.mailSource(from: record.inlineRFC)
        let receivedAt = AirmailDates.date(from: record.receivedAt) ?? AirmailDates.date(from: record.sentAt)
        let messageID = original.flatMap { AirmailMessageID.headerValue(in: $0) } ?? AirmailMessageID
            .normalize(record.messageID)
        let files = original == nil ? attachmentFiles(record: record, context: context) : []
        let raw = original ?? builtSource(
            record: record,
            body: body,
            messageID: messageID,
            context: context,
            files: files
        )
        return AirmailLetter(
            accountEmail: context.accountEmail,
            remoteUID: AirmailMessageID.remoteUID(shard: context.shard, idx: record.idx),
            serverUID: binding.serverUID,
            messageID: messageID,
            subject: subject,
            fromAddress: AirmailAddresses.display(from: record.sender),
            toAddresses: AirmailAddresses.emails(in: record.to),
            carbonCopy: AirmailAddresses.emails(in: record.cc),
            blindCarbonCopy: AirmailAddresses.emails(in: record.bcc),
            receivedAt: receivedAt,
            isRead: binding.isRead ?? AirmailFlags.isRead(record.flag),
            folder: AirmailFolders.choose(names: names),
            snippet: AirmailRFC.snippet(excerpt: record.excerpt, plain: original == nil ? plain : nil),
            hasAttachments: !files.isEmpty ||
                (original != nil && (record.attachmentCount > 0 || AirmailRFC.hasAttachment(raw))),
            rawSource: raw,
            isEmpty: original == nil && subject.isEmpty && plain.isEmpty && html.isEmpty && (record.excerpt ?? "")
                .isEmpty
        )
    }

    private static func attachmentFiles(
        record: AirmailMessageRecord,
        context: AirmailLetterContext
    ) -> [AirmailStoredFile] {
        AirmailAttachments.files(
            messageID: record.messageID,
            external: record.externalAttachments,
            inline: record.inlineAttachments,
            directory: context.attachmentsDirectory
        )
    }

    private static func builtSource(
        record: AirmailMessageRecord,
        body: AirmailBodyText,
        messageID: String?,
        context: AirmailLetterContext,
        files: [AirmailStoredFile]
    ) -> Data {
        let from = AirmailAddresses.display(from: record.sender)
        let receivedAt = AirmailDates.date(from: record.receivedAt) ?? AirmailDates.date(from: record.sentAt)
        let headers = AirmailRFCHeaders(
            idx: record.idx,
            date: receivedAt,
            from: from.isEmpty ? context.accountEmail : from,
            to: AirmailAddresses.emails(in: record.to),
            cc: AirmailAddresses.emails(in: record.cc),
            messageID: messageID ?? "airmail-\(context.shard)-\(record.idx)@vermail.local",
            subject: AirmailRFC.readable(record.subject)
        )
        return AirmailRFC.message(plain: body.plain, html: body.html, headers: headers, files: files)
    }
}

struct AirmailLetterContext {
    var accountEmail: String
    var shard: String
    var folders: [Int64: String]
    var attachmentsDirectory: URL
}
