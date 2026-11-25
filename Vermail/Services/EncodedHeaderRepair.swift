import Foundation
import MailStorage
import MIMEKit

enum EncodedHeaderRepair {
    /// Headers already saved with a split encoded-word stay raw until the raw message is read again.
    static func repairStoredHeaders(in database: MailDatabase) async {
        guard let ids = try? await database.messageIDsWithEncodedWords() else { return }
        for id in ids {
            await repair(id, in: database)
        }
    }

    private static func repair(_ id: Int64, in database: MailDatabase) async {
        guard let raw = try? await database.rawMessageData(id: id),
              let parsed = try? MIME.parse(raw)
        else { return }
        let toHeader = MessageMetadataExtractor.headerValue("To", in: parsed.headers) ?? ""
        let snippet = MessageMetadataExtractor.makeSnippet(
            plainBody: parsed.plainBody,
            htmlBody: parsed.htmlBody
        )
        try? await database.updateDecodedHeaders(
            id: id,
            subject: parsed.subject,
            fromAddress: MessageMetadataExtractor.headerValue("From", in: parsed.headers),
            toAddresses: MessageMetadataExtractor.splitAddressList(toHeader),
            snippet: snippet
        )
    }
}
