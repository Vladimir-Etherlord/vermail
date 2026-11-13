import SwiftUI
import UniformTypeIdentifiers

struct ComposeView: View {
    @Bindable var model: ComposeViewModel
    let onClose: () -> Void
    @Environment(AppPreferencesStore.self) private var preferences

    @State private var importingFiles = false
    @State private var addingAlias = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            editor
            if !model.draft.attachments.isEmpty {
                Divider()
                attachmentBar
            }
        }
        .frame(minWidth: 640, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: nil, perform: loadDroppedFiles)
        .fileImporter(
            isPresented: $importingFiles,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            importFiles(result)
        }
        .task {
            await model.loadSuggestions()
        }
        .onChange(of: model.signature) {
            model.persistSignature()
        }
        .alert(
            "Could Not Send",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: {
                    if !$0 {
                        model.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: model.errorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                senderPicker
                Spacer()
                Button("Add Alias") { addingAlias.toggle() }
                    .macButtonRollover()
                    .popover(isPresented: $addingAlias, arrowEdge: .bottom) {
                        aliasForm
                    }
                Button("Attach Files") { importingFiles = true }
                    .macButtonRollover()
                Button("Save Draft") {
                    Task { _ = await model.saveDraft() }
                }
                .macButtonRollover()
                .disabled(model.isSending)
                Button("Send") {
                    Task {
                        if await model.send() {
                            onClose()
                        }
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .macButtonRollover()
                .disabled(model.isSending)
            }
            RecipientField(
                title: "To:",
                primary: true,
                recipients: $model.draft.to,
                input: $model.toInput,
                suggestions: model.suggestions,
                onCommit: model.commitPendingInput
            )
            RecipientField(
                title: "Cc:",
                recipients: $model.draft.cc,
                input: $model.ccInput,
                suggestions: model.suggestions,
                onCommit: model.commitPendingInput
            )
            RecipientField(
                title: "Bcc:",
                recipients: $model.draft.bcc,
                input: $model.bccInput,
                suggestions: model.suggestions,
                onCommit: model.commitPendingInput
            )
            HStack {
                ComposeFieldLabel(title: "Subject:", primary: true)
                TextField("Subject", text: $model.draft.subject)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3.weight(.medium))
                    .controlSize(.large)
            }
            .padding(.top, 4)
            if let statusMessage = model.statusMessage {
                Text(verbatim: statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private var senderPicker: some View {
        Picker(
            "From:",
            selection: Binding(
                get: { model.draft.identityID },
                set: { model.selectIdentity($0) }
            )
        ) {
            ForEach(model.accounts) { account in
                Section {
                    ForEach(model.identities.filter { $0.accountID == account.id }) { identity in
                        Text(verbatim: identityLabel(identity)).tag(identity.id)
                    }
                } header: {
                    Text(verbatim: account.displayName)
                }
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 360)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $model.draft.body)
                .font(.system(size: preferences.preferences.composeFontSize))
                .padding(8)
            Text("Signature")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
            TextEditor(text: $model.signature)
                .font(.callout)
                .frame(minHeight: 56, maxHeight: 90)
                .padding(8)
                .background(.quaternary.opacity(0.25))
        }
    }

    private var attachmentBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.draft.attachments) { attachment in
                    HStack(spacing: 6) {
                        Image(systemName: "paperclip")
                        Text(verbatim: attachment.filename)
                            .lineLimit(1)
                        Text(verbatim: attachment.data.count.formatted(.byteCount(style: .file)))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Button {
                            model.removeAttachment(id: attachment.id)
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .macButtonRollover()
                        .help("Remove Attachment")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.background, in: Capsule())
                    .overlay(Capsule().stroke(.separator))
                }
            }
            .padding(10)
        }
    }

    private var aliasForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Alias")
                .font(.headline)
            TextField("Name", text: $model.aliasName)
            TextField("Email", text: $model.aliasEmail)
            HStack {
                Button("Cancel") { addingAlias = false }
                    .macButtonRollover()
                Button("Add") {
                    model.addAlias()
                    if model.errorMessage == nil {
                        addingAlias = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .macButtonRollover()
            }
        }
        .padding()
        .frame(width: 280)
    }

    private func identityLabel(_ identity: MailIdentity) -> String {
        ComposeMessageBuilder.formatAddress(name: identity.displayName, email: identity.emailAddress)
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result else { return }
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            guard let data = try? Data(contentsOf: url) else { continue }
            model.addAttachment(filename: url.lastPathComponent, data: data)
        }
    }

    private func loadDroppedFiles(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                let url = item as? URL ?? (item as? NSURL).map { $0 as URL }
                guard let url, let data = try? Data(contentsOf: url) else { return }
                Task { @MainActor in
                    model.addAttachment(filename: url.lastPathComponent, data: data)
                }
            }
        }
        return accepted
    }
}

/// AppKit push buttons shift the bezel on rollover with a short ease-out. The system change is easy to miss, so this
/// adds the same shift.
private struct MacButtonRollover: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.08 : 0))
                    .padding(1)
                    .allowsHitTesting(false)
            }
            .onHover { inside in
                withAnimation(.easeOut(duration: 0.15)) {
                    hovering = inside
                }
            }
    }
}

private extension View {
    func macButtonRollover() -> some View {
        modifier(MacButtonRollover())
    }
}
