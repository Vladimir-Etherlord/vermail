import MailCore
import MailStorage
import MIMEKit
import SwiftUI

struct MessageDetailView: View {
    let message: StoredMessage
    let parsedMessage: MIMEMessage?
    let currentFolder: MailFolderKind
    let shouldShowRemoteImageBanner: Bool
    let allowRemoteImages: Bool
    let onAllowImagesOnce: () -> Void
    let onAllowImagesAlways: () -> Void
    let onToggleRead: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void
    let onMove: (MailFolderKind) -> Void
    let onReply: () -> Void
    let onReplyAll: () -> Void
    let onForward: () -> Void
    let onEditDraft: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            Divider()

            if shouldShowRemoteImageBanner {
                remoteImageBanner
                Divider()
            }

            MessageWebView(
                htmlBody: parsedMessage?.htmlBody,
                plainBody: parsedMessage?.plainBody,
                allowRemoteImages: allowRemoteImages
            )

            if let attachments = parsedMessage?.attachments, !attachments.isEmpty {
                Divider()
                AttachmentBarView(attachments: attachments)
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                if let subject = message.subject, !subject.isEmpty {
                    Text(verbatim: subject)
                        .font(.title2.bold())
                        .textSelection(.enabled)
                } else {
                    Text("(No Subject)")
                        .font(.title2.bold())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(currentFolder.title)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }

            actionBar

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    if let from = message.fromAddress, !from.isEmpty {
                        HStack(spacing: 4) {
                            Text("From:")
                                .foregroundStyle(.secondary)
                            Text(verbatim: from)
                                .textSelection(.enabled)
                        }
                        .font(.callout)
                    }

                    if !message.toAddresses.isEmpty {
                        HStack(spacing: 4) {
                            Text("To:")
                                .foregroundStyle(.secondary)
                            Text(verbatim: message.toAddresses.joined(separator: ", "))
                                .textSelection(.enabled)
                        }
                        .font(.caption)
                    }

                    if let receivedAt = message.receivedAt {
                        Text(verbatim: receivedAt.formatted(date: .long, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
    }

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if message.folder == .drafts {
                    Button("Edit Draft", systemImage: "square.and.pencil", action: onEditDraft)
                }
                Button("Reply", systemImage: "arrowshape.turn.up.left", action: onReply)
                Button("Reply All", systemImage: "arrowshape.turn.up.left.2", action: onReplyAll)
                Button("Forward", systemImage: "arrowshape.turn.up.right", action: onForward)
            }
            HStack(spacing: 8) {
                Button("Archive", systemImage: "archivebox", action: onArchive)
                moveMenu
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
                Button(action: onToggleRead) {
                    Label(
                        message.isRead ? "Mark as Unread" : "Mark as Read",
                        systemImage: message.isRead ? "envelope.badge" : "envelope.open"
                    )
                }
            }
        }
        .buttonStyle(.bordered)
        .labelStyle(.titleAndIcon)
    }

    private var moveMenu: some View {
        Menu {
            ForEach(MailFolderKind.allCases, id: \.self) { folder in
                if folder != .allMail {
                    Button {
                        onMove(folder)
                    } label: {
                        Label {
                            Text(folder.title)
                        } icon: {
                            Image(systemName: folder.systemImage)
                        }
                    }
                }
            }
        } label: {
            Label("Move", systemImage: "folder")
        }
    }

    private var remoteImageBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "photo.badge.exclamationmark")
                .foregroundStyle(.secondary)
            Text("Remote images are blocked.")
                .font(.callout)
            Spacer()
            Button("Always", action: onAllowImagesAlways)
                .controlSize(.small)
            Button("Once", action: onAllowImagesOnce)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.45))
    }
}
