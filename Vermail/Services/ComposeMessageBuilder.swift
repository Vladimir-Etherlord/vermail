import Foundation
import MailCore
import MailStorage
import MIMEKit
import SMTPKit

enum ComposeMessageBuilder {
    static func newDraft(account: MailAccount, identity: MailIdentity) -> ComposeDraft {
        ComposeDraft(accountID: account.id, identityID: identity.id)
    }

    static func reply(to original: ComposeOriginal, identity: MailIdentity) -> ComposeDraft {
        ComposeDraft(
            accountID: original.accountID,
            identityID: identity.id,
            to: original.from.map { [$0] } ?? [],
            subject: prefixed("Re:", original.subject),
            body: ComposeQuoting.quotedBody(original)
        )
    }

    static func replyAll(
        to original: ComposeOriginal,
        identity: MailIdentity,
        ownAddresses: Set<String>
    ) -> ComposeDraft {
        let sender = original.from
        var copies = original.to + original.cc
        if let sender {
            copies.removeAll { emailAddress(in: $0)?.lowercased() == emailAddress(in: sender)?.lowercased() }
        }
        copies.removeAll { address in
            guard let email = emailAddress(in: address)?.lowercased() else { return false }
            return ownAddresses.contains(email)
        }
        return ComposeDraft(
            accountID: original.accountID,
            identityID: identity.id,
            to: sender.map { [$0] } ?? [],
            cc: copies,
            subject: prefixed("Re:", original.subject),
            body: ComposeQuoting.quotedBody(original)
        )
    }

    static func forward(original: ComposeOriginal, identity: MailIdentity) -> ComposeDraft {
        ComposeDraft(
            accountID: original.accountID,
            identityID: identity.id,
            subject: prefixed("Fwd:", original.subject),
            body: ComposeQuoting.forwardedBody(original),
            attachments: original.attachments
        )
    }

    static func edit(original: ComposeOriginal, identity: MailIdentity) -> ComposeDraft {
        ComposeDraft(
            existingMessageID: original.existingMessageID,
            remoteUID: original.remoteUID ?? "local-\(UUID().uuidString)",
            accountID: original.accountID,
            identityID: identity.id,
            to: original.to,
            cc: original.cc,
            bcc: original.bcc,
            subject: original.subject ?? "",
            body: original.body,
            attachments: original.attachments
        )
    }

    static func original(stored: StoredMessage, parsed: MIMEMessage?) -> ComposeOriginal {
        let headers = parsed?.headers ?? []
        let body = parsed?.plainBody ?? MessageMetadataExtractor.stripHTML(parsed?.htmlBody ?? "")
        let attachments = (parsed?.attachments ?? []).map { part in
            ComposeAttachment(
                filename: part.filename ?? "attachment",
                mimeType: part.contentType,
                data: part.data
            )
        }
        return ComposeOriginal(
            accountID: stored.accountID,
            from: stored.fromAddress,
            to: headerList("To", headers: headers, fallback: stored.toAddresses),
            cc: headerList("Cc", headers: headers, fallback: []),
            bcc: headerList("Bcc", headers: headers, fallback: []),
            subject: stored.subject,
            body: body.trimmingCharacters(in: .whitespacesAndNewlines),
            date: stored.receivedAt,
            attachments: attachments,
            existingMessageID: stored.id,
            remoteUID: stored.remoteUID
        )
    }

    static func smtpMessage(
        draft: ComposeDraft,
        identity: MailIdentity,
        signature: String
    ) -> SMTPMessage? {
        let recipients = uniqueEmails(draft.to + draft.cc + draft.bcc)
        guard !recipients.isEmpty else { return nil }
        let mime = outgoingMessage(
            draft: draft,
            identity: identity,
            signature: signature,
            includeBccHeader: false
        )
        return SMTPMessage(from: identity.emailAddress, recipients: recipients, data: MIME.build(mime))
    }

    static func rawMessage(
        draft: ComposeDraft,
        identity: MailIdentity,
        signature: String,
        includeBccHeader: Bool
    ) -> Data {
        MIME.build(
            outgoingMessage(
                draft: draft,
                identity: identity,
                signature: signature,
                includeBccHeader: includeBccHeader
            )
        )
    }

    static func composedBody(_ body: String, signature: String) -> String {
        let trimmedSignature = signature.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSignature.isEmpty {
            return body
        }
        let block = "-- \n\(trimmedSignature)"
        if body.contains(block) {
            return body
        }
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\n\n\(block)"
        }
        return "\(body)\n\n\(block)"
    }

    static func tokens(from raw: String) -> [String] {
        let normalized = raw.replacingOccurrences(of: ";", with: ",")
        return MessageMetadataExtractor.splitAddressList(normalized)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func emailAddress(in raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = trimmed.lastIndex(of: "<"),
           let end = trimmed.lastIndex(of: ">"),
           start < end
        {
            let email = trimmed[trimmed.index(after: start) ..< end]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if email.contains("@") {
                return email
            }
        }
        return trimmed.contains("@") ? trimmed : nil
    }

    static func formatAddress(name: String, email: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.caseInsensitiveCompare(email) == .orderedSame {
            return email
        }
        let escaped = trimmed
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\" <\(email)>"
    }

    private static func outgoingMessage(
        draft: ComposeDraft,
        identity: MailIdentity,
        signature: String,
        includeBccHeader: Bool
    ) -> MIMEOutgoingMessage {
        MIMEOutgoingMessage(
            from: formatAddress(name: identity.displayName, email: identity.emailAddress),
            to: draft.to,
            carbonCopy: draft.cc,
            blindCarbonCopy: draft.bcc,
            includesBlindCarbonCopyHeader: includeBccHeader,
            subject: draft.subject,
            plainBody: composedBody(draft.body, signature: signature),
            attachments: draft.attachments.map {
                MIMEAttachmentInput(filename: $0.filename, mimeType: $0.mimeType, data: $0.data)
            }
        )
    }

    private static func prefixed(_ prefix: String, _ subject: String?) -> String {
        let trimmed = subject?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return prefix
        }
        if trimmed.lowercased().hasPrefix(prefix.lowercased()) {
            return trimmed
        }
        return "\(prefix) \(trimmed)"
    }

    private static func headerList(_ name: String, headers: [MIMEHeader], fallback: [String]) -> [String] {
        guard let raw = MessageMetadataExtractor.headerValue(name, in: headers) else {
            return fallback
        }
        let parsed = MessageMetadataExtractor.splitAddressList(raw)
        return parsed.isEmpty ? fallback : parsed
    }

    private static func uniqueEmails(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            guard let email = emailAddress(in: value) else { continue }
            if seen.insert(email.lowercased()).inserted {
                result.append(email)
            }
        }
        return result
    }
}

struct ComposeOriginal: Equatable, Sendable {
    var accountID: UUID
    var from: String?
    var to: [String]
    var cc: [String]
    var bcc: [String]
    var subject: String?
    var body: String
    var date: Date?
    var attachments: [ComposeAttachment]
    var existingMessageID: Int64?
    var remoteUID: String?
}
