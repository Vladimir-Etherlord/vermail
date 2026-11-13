import SwiftUI

struct ComposeFieldLabel: View {
    let title: LocalizedStringResource
    var primary = false

    var body: some View {
        Text(title)
            .fontWeight(primary ? .semibold : .regular)
            .foregroundStyle(primary ? .primary : .secondary)
            .frame(width: 108, alignment: .trailing)
            .lineLimit(1)
    }
}

struct RecipientField: View {
    let title: LocalizedStringResource
    var primary = false
    @Binding var recipients: [String]
    @Binding var input: String
    let suggestions: [String]
    let onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ComposeFieldLabel(title: title, primary: primary)
                tokenField
            }
            if !matchingSuggestions.isEmpty {
                suggestionList
            }
        }
    }

    private var tokenField: some View {
        HStack(spacing: 6) {
            ForEach(recipients, id: \.self) { recipient in
                token(recipient)
            }
            TextField("", text: $input)
                .textFieldStyle(.plain)
                .onSubmit(onCommit)
        }
        .padding(6)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
    }

    private var suggestionList: some View {
        HStack {
            Spacer().frame(width: 80)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(matchingSuggestions, id: \.self) { suggestion in
                    Button {
                        recipients.append(suggestion)
                        input = ""
                    } label: {
                        Text(verbatim: suggestion)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
        }
    }

    private var matchingSuggestions: [String] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return suggestions
            .filter { suggestion in
                suggestion.localizedCaseInsensitiveContains(trimmed) && !recipients.contains(suggestion)
            }
            .prefix(6)
            .map(\.self)
    }

    private func token(_ recipient: String) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: recipient)
                .lineLimit(1)
            Button {
                recipients.removeAll { $0 == recipient }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.thinMaterial, in: Capsule())
    }
}
