import Foundation

struct ComposeAttachment: Identifiable, Equatable, Sendable {
    var id: UUID
    var filename: String
    var mimeType: String
    var data: Data

    init(id: UUID = UUID(), filename: String, mimeType: String, data: Data) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
    }
}

struct ComposeDraft: Identifiable, Equatable, Sendable {
    var id: UUID
    var existingMessageID: Int64?
    var remoteUID: String
    var accountID: UUID
    var identityID: UUID
    var to: [String]
    var cc: [String]
    var bcc: [String]
    var subject: String
    var body: String
    var attachments: [ComposeAttachment]

    init(
        id: UUID = UUID(),
        existingMessageID: Int64? = nil,
        remoteUID: String = "local-\(UUID().uuidString)",
        accountID: UUID,
        identityID: UUID,
        to: [String] = [],
        cc: [String] = [],
        bcc: [String] = [],
        subject: String = "",
        body: String = "",
        attachments: [ComposeAttachment] = []
    ) {
        self.id = id
        self.existingMessageID = existingMessageID
        self.remoteUID = remoteUID
        self.accountID = accountID
        self.identityID = identityID
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.body = body
        self.attachments = attachments
    }
}

enum ComposeRequest: Equatable {
    case newMessage
    case reply
    case replyAll
    case forward
    case editDraft
}
