import Foundation

enum MIMEParser {
    static func parse(_ raw: Data) throws -> MIMEMessage {
        let (headerData, bodyData) = splitHeadersAndBody(raw)
        let headers = parseHeaders(from: headerData)
        let parts = parseEntity(headers: headers, body: bodyData, defaultContentType: "text/plain")

        var plainBody: String?
        var htmlBody: String?
        let attachments = parts.filter(\.isAttachment)

        for part in parts where !part.isAttachment {
            if part.contentType.hasPrefix("text/plain"), plainBody == nil {
                plainBody = part.text
            } else if part.contentType.hasPrefix("text/html"), htmlBody == nil {
                htmlBody = part.text
            }
        }

        return MIMEMessage(
            headers: headers,
            subject: MIMECodec.headerValue(headers, "Subject"),
            plainBody: plainBody,
            htmlBody: htmlBody,
            parts: parts,
            attachments: attachments
        )
    }

    static func splitHeadersAndBody(_ data: Data) -> (Data, Data) {
        if let range = data.range(of: Data("\r\n\r\n".utf8)) {
            return (data[..<range.lowerBound], data[range.upperBound...])
        }
        if let range = data.range(of: Data("\n\n".utf8)) {
            return (data[..<range.lowerBound], data[range.upperBound...])
        }
        return (data, Data())
    }

    static func parseHeaders(from data: Data) -> [MIMEHeader] {
        let raw = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let lines = raw.replacingOccurrences(of: "\r\n", with: "\n").split(
            separator: "\n",
            omittingEmptySubsequences: false
        )

        var headers: [MIMEHeader] = []
        var currentName: String?
        var currentValue = ""

        func flush() {
            guard let currentName else { return }
            let value = MIMECodec.decodeRFC2047(currentValue.trimmingCharacters(in: .whitespaces))
            headers.append(MIMEHeader(name: currentName, value: value))
        }

        for lineSub in lines {
            let line = String(lineSub)
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                currentValue += " " + line.trimmingCharacters(in: .whitespaces)
                continue
            }

            flush()
            currentName = nil
            currentValue = ""

            guard let split = line.firstIndex(of: ":") else { continue }
            currentName = String(line[..<split]).trimmingCharacters(in: .whitespaces)
            currentValue = String(line[line.index(after: split)...]).trimmingCharacters(in: .whitespaces)
        }
        flush()
        return headers
    }

    static func parseEntity(headers: [MIMEHeader], body: Data, defaultContentType: String) -> [MIMEPart] {
        let parsedType = MIMECodec
            .parseContentType(MIMECodec.headerValue(headers, "Content-Type") ?? defaultContentType)
        let transfer = MIMECodec.headerValue(headers, "Content-Transfer-Encoding")?.lowercased()
        let dispositionRaw = MIMECodec.headerValue(headers, "Content-Disposition")
        let disposition = dispositionRaw.map(MIMECodec.parseContentType)

        if parsedType.mediaType.hasPrefix("multipart/"),
           let boundary = parsedType.parameters["boundary"],
           !boundary.isEmpty
        {
            let sections = splitMultipart(body: body, boundary: boundary)
            var parts: [MIMEPart] = []
            for section in sections {
                let (subHeaderData, subBodyData) = splitHeadersAndBody(section)
                let subHeaders = parseHeaders(from: subHeaderData)
                parts.append(contentsOf: parseEntity(
                    headers: subHeaders,
                    body: subBodyData,
                    defaultContentType: "text/plain"
                ))
            }
            return parts
        }

        let decoded = MIMECodec.decodeTransferEncoding(transfer, body: body)
        let charset = parsedType.parameters["charset"]
        let text = parsedType.mediaType.hasPrefix("text/") ? MIMECodec.decodeText(decoded, charset: charset) : nil

        let filename = disposition?.parameters["filename"] ?? parsedType.parameters["name"]
        let isAttachment =
            (disposition?.mediaType.contains("attachment") == true) ||
            (filename?.isEmpty == false)

        return [
            MIMEPart(
                headers: headers,
                contentType: parsedType.mediaType,
                charset: charset,
                transferEncoding: transfer,
                contentDisposition: disposition?.mediaType,
                filename: filename,
                data: decoded,
                text: text,
                isAttachment: isAttachment
            ),
        ]
    }

    static func splitMultipart(body: Data, boundary: String) -> [Data] {
        let raw = String(data: body, encoding: .isoLatin1) ?? String(decoding: body, as: UTF8.self)
        let lines = raw.replacingOccurrences(of: "\r\n", with: "\n").split(
            separator: "\n",
            omittingEmptySubsequences: false
        )

        let marker = "--\(boundary)"
        let closing = "--\(boundary)--"

        var parts: [String] = []
        var current: [String] = []
        var inPart = false

        for lineSub in lines {
            let line = String(lineSub)
            if line == marker {
                if inPart {
                    parts.append(current.joined(separator: "\n"))
                    current = []
                }
                inPart = true
                continue
            }
            if line == closing {
                if inPart {
                    parts.append(current.joined(separator: "\n"))
                }
                break
            }
            if inPart {
                current.append(line)
            }
        }

        return parts.compactMap { $0.data(using: .isoLatin1) }
    }
}
