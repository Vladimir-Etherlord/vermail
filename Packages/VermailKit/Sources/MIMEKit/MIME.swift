import Foundation

public struct MIMEHeader: Sendable, Hashable {
    public var name: String
    public var value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct MIMEPart: Sendable, Hashable {
    public var headers: [MIMEHeader]
    public var contentType: String
    public var charset: String?
    public var transferEncoding: String?
    public var contentDisposition: String?
    public var filename: String?
    public var data: Data
    public var text: String?
    public var isAttachment: Bool

    public init(
        headers: [MIMEHeader],
        contentType: String,
        charset: String?,
        transferEncoding: String?,
        contentDisposition: String?,
        filename: String?,
        data: Data,
        text: String?,
        isAttachment: Bool
    ) {
        self.headers = headers
        self.contentType = contentType
        self.charset = charset
        self.transferEncoding = transferEncoding
        self.contentDisposition = contentDisposition
        self.filename = filename
        self.data = data
        self.text = text
        self.isAttachment = isAttachment
    }
}

public struct MIMEMessage: Sendable, Hashable {
    public var headers: [MIMEHeader]
    public var subject: String?
    public var plainBody: String?
    public var htmlBody: String?
    public var parts: [MIMEPart]
    public var attachments: [MIMEPart]

    public init(
        headers: [MIMEHeader],
        subject: String?,
        plainBody: String?,
        htmlBody: String?,
        parts: [MIMEPart],
        attachments: [MIMEPart]
    ) {
        self.headers = headers
        self.subject = subject
        self.plainBody = plainBody
        self.htmlBody = htmlBody
        self.parts = parts
        self.attachments = attachments
    }
}

public struct MIMEAttachmentInput: Sendable, Hashable {
    public var filename: String
    public var mimeType: String
    public var data: Data

    public init(filename: String, mimeType: String, data: Data) {
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
    }
}

public struct MIMEOutgoingMessage: Sendable, Hashable {
    public var from: String
    public var to: [String]
    public var carbonCopy: [String]
    public var subject: String
    public var plainBody: String
    public var htmlBody: String?
    public var attachments: [MIMEAttachmentInput]

    public init(
        from: String,
        to: [String],
        carbonCopy: [String] = [],
        subject: String,
        plainBody: String,
        htmlBody: String? = nil,
        attachments: [MIMEAttachmentInput] = []
    ) {
        self.from = from
        self.to = to
        self.carbonCopy = carbonCopy
        self.subject = subject
        self.plainBody = plainBody
        self.htmlBody = htmlBody
        self.attachments = attachments
    }
}

public enum MIMEError: Error, Equatable, Sendable {
    case malformedMessage
}

public enum MIME {
    /// RFC 5322 line ending.
    public static let lineBreak = "\r\n"

    public static func parse(_ raw: Data) throws -> MIMEMessage {
        try MIMEParser.parse(raw)
    }

    public static func build(_ message: MIMEOutgoingMessage) -> Data {
        MIMEBuilder.build(message)
    }
}
