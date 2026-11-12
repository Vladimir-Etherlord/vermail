import Foundation

enum MIMEBuilder {
    private struct EntityContent {
        let header: String
        let body: String
    }

    static func build(_ message: MIMEOutgoingMessage) -> Data {
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"

        var headers: [String] = [
            "From: \(message.from)",
            "To: \(message.to.joined(separator: ", "))",
        ]
        if !message.carbonCopy.isEmpty {
            headers.append("Cc: \(message.carbonCopy.joined(separator: ", "))")
        }
        if message.includesBlindCarbonCopyHeader, !message.blindCarbonCopy.isEmpty {
            headers.append("Bcc: \(message.blindCarbonCopy.joined(separator: ", "))")
        }
        headers += [
            "Subject: \(MIMECodec.encodeRFC2047IfNeeded(message.subject))",
            "Date: \(dateFormatter.string(from: now))",
            "MIME-Version: 1.0",
        ]

        let content = buildBody(plain: message.plainBody, html: message.htmlBody, attachments: message.attachments)
        headers.append(content.header)

        let serialized = headers.joined(separator: MIME.lineBreak) + MIME.lineBreak + MIME.lineBreak + content.body
        return Data(serialized.utf8)
    }

    private static func buildBody(plain: String, html: String?, attachments: [MIMEAttachmentInput]) -> EntityContent {
        let plainPart = textPart(contentType: "text/plain", text: plain)

        let primaryBody: EntityContent
        if let html {
            let alternativeBoundary = "vermail-alt-\(UUID().uuidString)"
            let htmlPart = textPart(contentType: "text/html", text: html)
            var body = ""
            body += "--\(alternativeBoundary)\(MIME.lineBreak)"
            body += plainPart.header + MIME.lineBreak + MIME.lineBreak + plainPart.body + MIME.lineBreak
            body += "--\(alternativeBoundary)\(MIME.lineBreak)"
            body += htmlPart.header + MIME.lineBreak + MIME.lineBreak + htmlPart.body + MIME.lineBreak
            body += "--\(alternativeBoundary)--"

            primaryBody = EntityContent(
                header: "Content-Type: multipart/alternative; boundary=\"\(alternativeBoundary)\"",
                body: body
            )
        } else {
            primaryBody = plainPart
        }

        guard !attachments.isEmpty else {
            return primaryBody
        }

        let mixedBoundary = "vermail-mixed-\(UUID().uuidString)"
        var body = ""
        body += "--\(mixedBoundary)\(MIME.lineBreak)"
        body += primaryBody.header + MIME.lineBreak + MIME.lineBreak + primaryBody.body + MIME.lineBreak

        for attachment in attachments {
            let encodedName = MIMECodec.encodeRFC2231Value(attachment.filename)
            let base64 = attachment.data.base64EncodedString()
            let folded = stride(from: 0, to: base64.count, by: 76).map { index in
                let start = base64.index(base64.startIndex, offsetBy: index)
                let end = base64.index(start, offsetBy: min(76, base64.distance(from: start, to: base64.endIndex)))
                return String(base64[start ..< end])
            }.joined(separator: MIME.lineBreak)

            body += "--\(mixedBoundary)\(MIME.lineBreak)"
            body += "Content-Type: \(attachment.mimeType); name*=\(encodedName)\(MIME.lineBreak)"
            body += "Content-Disposition: attachment; filename*=\(encodedName)\(MIME.lineBreak)"
            body += "Content-Transfer-Encoding: base64\(MIME.lineBreak)\(MIME.lineBreak)"
            body += folded + MIME.lineBreak
        }

        body += "--\(mixedBoundary)--"
        return EntityContent(
            header: "Content-Type: multipart/mixed; boundary=\"\(mixedBoundary)\"",
            body: body
        )
    }

    private static func textPart(contentType: String, text: String) -> EntityContent {
        let header =
            "Content-Type: \(contentType); charset=utf-8\(MIME.lineBreak)" +
            "Content-Transfer-Encoding: quoted-printable"
        return EntityContent(
            header: header,
            body: MIMECodec.encodeQuotedPrintable(Data(text.utf8))
        )
    }
}
