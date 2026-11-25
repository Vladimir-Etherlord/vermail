import Testing
@testable import Vermail

struct AttachmentPreviewTests {
    @Test func popularFormatsGetThumbnails() {
        #expect(AttachmentPreview.canPreview(filename: "report.PDF"))
        #expect(AttachmentPreview.canPreview(filename: "photo.jpeg"))
        #expect(AttachmentPreview.canPreview(filename: "scan.heic"))
        #expect(AttachmentPreview.canPreview(filename: "page.html"))
        #expect(!AttachmentPreview.canPreview(filename: "archive.zip"))
        #expect(!AttachmentPreview.canPreview(filename: "notes"))
    }
}
