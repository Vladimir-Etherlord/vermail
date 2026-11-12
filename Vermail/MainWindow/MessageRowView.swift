import MailCore
import MailStorage
import SwiftUI

struct MessageRowView: View {
    let message: StoredMessage
    let accountColor: Color?
    var showAvatar: Bool = true
    var showPreview: Bool = true

    var body: some View {
        let sender = SenderDisplay(raw: message.fromAddress)

        HStack(alignment: .top, spacing: 10) {
            if showAvatar {
                avatar(sender)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let accountColor {
                        Circle()
                            .fill(accountColor)
                            .frame(width: 7, height: 7)
                    }

                    Text(verbatim: sender.name)
                        .font(.headline)
                        .fontWeight(message.isRead ? .regular : .semibold)
                        .lineLimit(1)

                    Spacer()

                    if let receivedAt = message.receivedAt {
                        Text(verbatim: receivedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 4) {
                    if let subject = message.subject, !subject.isEmpty {
                        Text(verbatim: subject)
                            .font(.subheadline)
                            .fontWeight(message.isRead ? .regular : .medium)
                            .lineLimit(1)
                    } else {
                        Text("(No Subject)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    if message.hasAttachments {
                        Image(systemName: "paperclip")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if showPreview, let snippet = message.snippet, !snippet.isEmpty {
                    Text(verbatim: snippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func avatar(_ sender: SenderDisplay) -> some View {
        ZStack(alignment: .topLeading) {
            Circle()
                .fill(sender.avatarColor.gradient)
                .frame(width: 34, height: 34)
                .overlay {
                    Text(verbatim: sender.initials)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                }

            if !message.isRead {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 9, height: 9)
                    .offset(x: -3, y: -2)
            }
        }
    }
}

struct SenderDisplay {
    let name: String
    let email: String
    let initials: String
    let avatarColor: Color

    private static let palette: [Color] = [
        .blue, .indigo, .purple, .pink, .orange, .teal, .green, .cyan,
    ]

    init(raw: String?) {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = trimmed.firstIndex(of: "<"),
           let end = trimmed[start...].firstIndex(of: ">")
        {
            let displayPart = trimmed[..<start]
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"")))
            let emailPart = String(trimmed[trimmed.index(after: start) ..< end])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            email = emailPart.isEmpty ? trimmed : emailPart
            name = displayPart.isEmpty ? email : displayPart
        } else {
            email = trimmed
            name = trimmed.isEmpty ? "?" : trimmed
        }

        let words = name
            .split { !$0.isLetter && !$0.isNumber }
            .prefix(2)
        let letters = words.compactMap(\.first).map { String($0).uppercased() }.joined()
        initials = letters.isEmpty ? "?" : letters

        let hash = email.lowercased().utf8.reduce(0) { ($0 &* 31) &+ Int($1) }
        avatarColor = Self.palette[abs(hash) % Self.palette.count]
    }
}
