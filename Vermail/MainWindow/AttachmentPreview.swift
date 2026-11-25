import AppKit
import MIMEKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

enum AttachmentPreview {
    static func canPreview(filename: String) -> Bool {
        let ext = (filename as NSString).pathExtension
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .pdf) || type.conforms(to: .html)
    }

    @MainActor
    static func thumbnail(data: Data, filename: String) async -> NSImage? {
        guard canPreview(filename: filename), data.count <= 40_000_000 else { return nil }
        let key = cacheKey(data: data, filename: filename)
        if let cached = AttachmentPreviewCache.shared.image(for: key) {
            return cached
        }
        guard let image = await render(data: data, filename: filename) else { return nil }
        AttachmentPreviewCache.shared.store(image, for: key)
        return image
    }

    static func cacheKey(data: Data, filename: String) -> String {
        var hasher = Hasher()
        hasher.combine(filename)
        hasher.combine(data.count)
        hasher.combine(Data(data.prefix(64)))
        hasher.combine(Data(data.suffix(64)))
        return String(hasher.finalize())
    }

    private static func render(data: Data, filename: String) async -> NSImage? {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "VermailThumb-\(UUID().uuidString)", directoryHint: .isDirectory)
        let file = folder.appending(path: safeFilename(filename))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            let request = QLThumbnailGenerator.Request(
                fileAt: file,
                size: CGSize(width: 360, height: 240),
                scale: 2,
                representationTypes: .thumbnail
            )
            let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            try? FileManager.default.removeItem(at: folder)
            return representation.nsImage
        } catch {
            try? FileManager.default.removeItem(at: folder)
            return nil
        }
    }

    private static func safeFilename(_ filename: String) -> String {
        let cleaned = filename
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "attachment" : cleaned
    }
}

@MainActor
final class AttachmentPreviewCache {
    static let shared = AttachmentPreviewCache()

    private let images: NSCache<NSString, NSImage> = {
        let images = NSCache<NSString, NSImage>()
        images.countLimit = 40
        return images
    }()

    func image(for key: String) -> NSImage? {
        images.object(forKey: key as NSString)
    }

    func store(_ image: NSImage, for key: String) {
        images.setObject(image, forKey: key as NSString)
    }
}

struct AttachmentThumbnailCard: View {
    let attachment: MIMEPart
    var onOpen: () -> Void
    var onSave: () -> Void

    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            preview
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: filename)
                        .font(.callout)
                        .lineLimit(2)
                    Text(verbatim: attachment.data.count.formatted(.byteCount(style: .file)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(action: onSave) {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Save Attachment")
            }
        }
        .padding(8)
        .frame(width: 196)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 0.5)
        )
        .task(id: AttachmentPreview.cacheKey(data: attachment.data, filename: filename)) {
            thumbnail = await AttachmentPreview.thumbnail(data: attachment.data, filename: filename)
        }
    }

    private var filename: String {
        attachment.filename ?? "attachment"
    }

    private var preview: some View {
        Button(action: onOpen) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white)
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .padding(4)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(.separator, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
