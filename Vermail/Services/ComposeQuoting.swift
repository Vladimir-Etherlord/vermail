import Foundation

enum ComposeQuoting {
    static func quotedBody(_ original: ComposeOriginal) -> String {
        let sender = original.from ?? String(localized: "Unknown sender")
        let quoted = original.body.components(separatedBy: "\n").map { "> \($0)" }.joined(separator: "\n")
        let header = quoteHeader(sender: sender, date: original.date)
        return "\n\n\(header)\n\(quoted)"
    }

    static func forwardedBody(_ original: ComposeOriginal) -> String {
        var lines = ["", "", "---------- \(String(localized: "Forwarded message")) ----------"]
        if let from = original.from {
            lines.append("\(String(localized: "From:")) \(from)")
        }
        if let date = original.date {
            lines.append("\(String(localized: "Date:")) \(date.formatted(date: .long, time: .shortened))")
        }
        lines.append("\(String(localized: "Subject:")) \(original.subject ?? "")")
        if !original.to.isEmpty {
            lines.append("\(String(localized: "To:")) \(original.to.joined(separator: ", "))")
        }
        lines.append("")
        lines.append(original.body)
        return lines.joined(separator: "\n")
    }

    private static func quoteHeader(sender: String, date: Date?) -> String {
        guard let date else {
            return String(format: String(localized: "%1$@ wrote:"), locale: .current, sender)
        }
        let dateText = date.formatted(date: .abbreviated, time: .shortened)
        return String(
            format: String(localized: "On %1$@, %2$@ wrote:"),
            locale: .current,
            dateText,
            sender
        )
    }
}
