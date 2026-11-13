import AppKit
import MIMEKit
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct AttachmentBarView: View {
    let attachments: [MIMEPart]

    @State private var quickLookURL: URL?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(attachments.enumerated()), id: \.offset) { _, attachment in
                    attachmentCard(attachment)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.quaternary.opacity(0.35))
        .quickLookPreview($quickLookURL)
    }

    private func attachmentCard(_ attachment: MIMEPart) -> some View {
        let filename = attachment.filename ?? "attachment"
        let sizeText = attachment.data.count.formatted(.byteCount(style: .file))
        let icon = fileIcon(for: filename)

        return HStack(spacing: 8) {
            Button {
                openQuickLook(attachment: attachment, filename: filename)
            } label: {
                HStack(spacing: 8) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: filename)
                            .font(.callout)
                            .lineLimit(1)
                        Text(verbatim: sizeText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            Button {
                saveToDownloads(attachment, filename: filename)
            } label: {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Save Attachment")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 0.5)
        )
        .contextMenu {
            Button("Quick Look") {
                openQuickLook(attachment: attachment, filename: filename)
            }
            Button("Save Attachment") {
                saveToDownloads(attachment, filename: filename)
            }
            Button("Save As…") {
                saveWithPanel(attachment, filename: filename)
            }
        }
    }

    private func fileIcon(for filename: String) -> NSImage {
        let ext = (filename as NSString).pathExtension
        let type = ext.isEmpty ? UTType.data : (UTType(filenameExtension: ext) ?? .data)
        return NSWorkspace.shared.icon(for: type)
    }

    private func openQuickLook(attachment: MIMEPart, filename: String) {
        let safeName = filename.replacingOccurrences(of: "/", with: "_")
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "VermailQuickLook-\(UUID().uuidString)", directoryHint: .isDirectory)
        let fileURL = folder.appending(path: safeName)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try attachment.data.write(to: fileURL, options: .atomic)
            quickLookURL = fileURL
        } catch {
            NSSound.beep()
        }
    }

    private func saveToDownloads(_ attachment: MIMEPart, filename: String) {
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            NSSound.beep()
            return
        }
        let destination = uniqueFileURL(in: downloads, filename: safeFilename(filename))
        do {
            try attachment.data.write(to: destination, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            NSSound.beep()
        }
    }

    private func saveWithPanel(_ attachment: MIMEPart, filename: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = safeFilename(filename)
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try attachment.data.write(to: destination, options: .atomic)
        } catch {
            NSSound.beep()
        }
    }

    private func safeFilename(_ filename: String) -> String {
        let cleaned = filename
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "attachment" : cleaned
    }

    private func uniqueFileURL(in directory: URL, filename: String) -> URL {
        let file = URL(fileURLWithPath: filename)
        let stem = file.deletingPathExtension().lastPathComponent
        let ext = file.pathExtension
        var candidate = directory.appending(path: filename)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            let name = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            candidate = directory.appending(path: name)
            index += 1
        }
        return candidate
    }
}
