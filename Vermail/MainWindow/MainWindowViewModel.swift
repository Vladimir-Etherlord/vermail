import Foundation
import MailCore
import MailStorage
import MIMEKit
import Observation

@Observable
@MainActor
final class MainWindowViewModel {
    let accountStore: AccountStore
    let secretStore: any AccountSecretStore
    let identityStore: ComposeIdentityStore
    let preferencesStore: AppPreferencesStore
    private let database: MailDatabase
    let syncEngine: MailSyncEngine
    private let imagePolicyStore: RemoteImagePolicyStore
    private let sendService: MailSendService
    let systemServices: SystemServices

    private var searchTask: Task<Void, Never>?
    /// Bumped when the user acts on the open message, so a delayed mark-as-read cannot overwrite that action.
    private var selectionEpoch = 0
    var lastCheckedAt: [UUID: Date] = [:]
    var checkLoop: Task<Void, Never>?
    var wakeMonitor: SleepWakeMonitor?
    var wantsFullCheck = false

    var accounts: [MailAccount] = []
    var selectedMailbox: Mailbox = .init(folder: .inbox, scope: .unified)
    var messages: [StoredMessage] = []
    var selectedMessageIDs: Set<Int64> = []
    var selectedMessageID: Int64?
    var selectedParsedMessage: MIMEMessage?
    var searchQuery: String = ""
    var showUnreadOnly: Bool = false
    var unreadCounts: UnreadCounts = .init()
    var syncStates: [UUID: AccountSyncState] = [:]
    var isSyncing: Bool = false
    var allowedOnceMessageIDs: Set<Int64> = []
    var pendingDeleteIDs: [Int64] = []
    var isDeleteConfirmationPresented = false
    var pendingEmptyTrash: Mailbox?
    var isEmptyTrashConfirmationPresented = false
    var lastError: String?
    let composeWindows = ComposeWindowPresenter()
    let messageWindows = MessageWindowPresenter()

    init(
        database: MailDatabase,
        accountStore: AccountStore,
        syncEngine: MailSyncEngine,
        imagePolicyStore: RemoteImagePolicyStore = RemoteImagePolicyStore(),
        identityStore: ComposeIdentityStore? = nil,
        sendService: MailSendService? = nil,
        secretStore: (any AccountSecretStore)? = nil,
        preferencesStore: AppPreferencesStore = AppPreferencesStore(),
        systemServices: SystemServices = .quiet,
        initialAccounts: [MailAccount]? = nil
    ) {
        self.database = database
        self.accountStore = accountStore
        self.syncEngine = syncEngine
        self.imagePolicyStore = imagePolicyStore
        let resolvedIdentityStore = identityStore ?? ComposeIdentityStore()
        self.identityStore = resolvedIdentityStore
        let resolvedSecrets = secretStore ?? InMemorySecretStore()
        self.secretStore = resolvedSecrets
        self.preferencesStore = preferencesStore
        self.systemServices = systemServices
        self.sendService = sendService ?? MailSendService(database: database, secretStore: resolvedSecrets)
        if let initialAccounts {
            accounts = initialAccounts
        }
    }

    var selectedMessage: StoredMessage? {
        guard let selectedMessageID else { return nil }
        return messages.first { $0.id == selectedMessageID }
    }

    var isRemoteImagesAllowedForSelectedMessage: Bool {
        guard let message = selectedMessage else { return false }
        if allowedOnceMessageIDs.contains(message.id) {
            return true
        }
        return imagePolicyStore.isAlwaysAllowed(sender: message.fromAddress)
    }

    var shouldShowRemoteImageBanner: Bool {
        guard !isRemoteImagesAllowedForSelectedMessage else { return false }
        return RemoteImagePolicyStore.containsRemoteImages(in: selectedParsedMessage?.htmlBody)
    }

    var accountByID: [UUID: MailAccount] {
        Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
    }

    func loadInitialData() async {
        do {
            accounts = try accountStore.loadAccounts()
        } catch {
            lastError = error.localizedDescription
        }
        await reloadMessages()
    }

    func reloadMessages() async {
        do {
            let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedQuery.isEmpty {
                messages = try await database.messages(
                    in: selectedMailbox,
                    accounts: accounts,
                    unreadOnly: showUnreadOnly
                )
            } else {
                messages = try await database.searchMessages(
                    query: trimmedQuery,
                    in: selectedMailbox,
                    accounts: accounts,
                    unreadOnly: showUnreadOnly
                )
            }
            unreadCounts = try await database.unreadCounts(accounts: accounts)

            let visible = Set(messages.map(\.id))
            selectedMessageIDs = selectedMessageIDs.intersection(visible)
            if let selectedMessageID, !visible.contains(selectedMessageID) {
                let keepReadMessageOpen = showUnreadOnly &&
                    searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if !keepReadMessageOpen {
                    self.selectedMessageID = nil
                    selectedParsedMessage = nil
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
        applyDockBadge()
    }

    func updateSearchQuery(_ query: String) {
        searchQuery = query
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await self?.reloadMessages()
        }
    }

    func selectMailbox(_ mailbox: Mailbox) async {
        selectedMailbox = mailbox
        selectedMessageIDs = []
        selectedMessageID = nil
        selectedParsedMessage = nil
        await reloadMessages()
    }

    func setShowUnreadOnly(_ unreadOnly: Bool) async {
        showUnreadOnly = unreadOnly
        await reloadMessages()
    }

    /// Stores the list selection immediately. Loading the open message happens afterwards.
    func applyMessageSelection(_ ids: Set<Int64>) {
        selectedMessageIDs = ids
        let focus = focusedMessageID(in: ids)
        Task { await selectMessage(focus, replacingSelection: false) }
    }

    func focusedMessageID(in ids: Set<Int64>) -> Int64? {
        if let selectedMessageID, ids.contains(selectedMessageID) {
            return selectedMessageID
        }
        return messages.first { ids.contains($0.id) }?.id
    }

    func idsForListActions() -> [Int64] {
        var ids = selectedMessageIDs
        if ids.isEmpty, let selectedMessageID {
            ids = [selectedMessageID]
        }
        let ordered = messages.map(\.id).filter { ids.contains($0) }
        if ordered.isEmpty, let selectedMessageID, ids.contains(selectedMessageID) {
            return [selectedMessageID]
        }
        return ordered
    }

    func selectMessage(_ id: Int64?, replacingSelection: Bool = true) async {
        if replacingSelection {
            selectedMessageIDs = id.map { [$0] } ?? []
        }
        if selectedMessageID == id, id == nil || selectedParsedMessage != nil {
            return
        }
        let isNewSelection = selectedMessageID != id
        if isNewSelection {
            selectionEpoch += 1
            selectedMessageID = id
            selectedParsedMessage = nil
        }
        let epoch = selectionEpoch
        guard let id else { return }

        do {
            if selectedParsedMessage == nil {
                let rawData = try await database.rawMessageData(id: id)
                guard selectedMessageID == id, epoch == selectionEpoch else { return }
                selectedParsedMessage = try MIME.parse(rawData)
            }
            guard isNewSelection else { return }
            await markReadIfStillSelected(id, epoch: epoch)
        } catch {
            selectedParsedMessage = nil
            lastError = error.localizedDescription
        }
    }

    func toggleRead(ids: [Int64]) async {
        guard !ids.isEmpty else { return }
        selectionEpoch += 1
        let targetMessages = messages.filter { ids.contains($0.id) }
        let shouldMarkRead = targetMessages.contains { !$0.isRead }
        do {
            try await syncEngine.setMessagesRead(shouldMarkRead, ids: ids, accounts: accounts)
            await reloadMessages()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func markReadIfStillSelected(_ id: Int64, epoch: Int) async {
        guard selectedMessageID == id, epoch == selectionEpoch, let message = messages.first(where: { $0.id == id }),
              !message.isRead else { return }
        let delay = preferencesStore.preferences.markAsReadDelaySeconds
        if delay > 0 {
            try? await Task.sleep(for: .seconds(delay))
        }
        guard selectedMessageID == id, epoch == selectionEpoch else { return }
        do {
            try await syncEngine.setMessagesRead(true, ids: [id], accounts: accounts)
            await reloadMessages()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func allowRemoteImagesOnce() {
        guard let selectedMessageID else { return }
        allowRemoteImagesOnce(messageID: selectedMessageID)
    }

    func allowRemoteImagesAlways() {
        allowRemoteImagesAlways(sender: selectedMessage?.fromAddress)
    }

    func makeComposeViewModel(for request: ComposeRequest) -> ComposeViewModel? {
        ComposeSessionFactory.make(
            request: request,
            context: ComposeSessionFactory.Context(
                accounts: accounts,
                selectedMailbox: selectedMailbox,
                selectedMessage: selectedMessage,
                parsedMessage: selectedParsedMessage,
                database: database,
                identityStore: identityStore,
                sendService: sendService,
                defaultAccountID: preferencesStore.preferences.defaultAccountID,
                includeSignature: preferencesStore.preferences.includeSignature
            )
        )
    }
}

extension MainWindowViewModel {
    func move(ids: [Int64], to folder: MailFolderKind) async {
        guard !ids.isEmpty else { return }
        let nextID = neighborID(afterRemoving: ids)
        selectionEpoch += 1
        do {
            try await syncEngine.moveMessages(ids: ids, to: folder, accounts: accounts)
            await reloadMessages()
            await revealMessage(nextID)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func requestEmptyTrash(_ mailbox: Mailbox) {
        pendingEmptyTrash = mailbox
        isEmptyTrashConfirmationPresented = true
    }

    func emptyTrash(_ mailbox: Mailbox) async {
        do {
            let ids = try await allMessageIDs(in: mailbox)
            await delete(ids: ids)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func allMessageIDs(in mailbox: Mailbox) async throws -> [Int64] {
        var ids: [Int64] = []
        var offset = 0
        while true {
            let batch = try await database.messages(in: mailbox, accounts: accounts, limit: 200, offset: offset)
            ids.append(contentsOf: batch.map(\.id))
            if batch.count < 200 {
                return ids
            }
            offset += batch.count
        }
    }

    func delete(ids: [Int64]) async {
        guard !ids.isEmpty else { return }
        let nextID = focusedMessageID(afterDeleting: ids)
        selectionEpoch += 1
        let removed = Set(ids)
        let permanently = messages.filter { removed.contains($0.id) }.allSatisfy { $0.folder == .trash }
        do {
            try await syncEngine.deleteMessages(ids: ids, permanently: permanently, accounts: accounts)
            await reloadMessages()
            await revealMessage(nextID)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func openMessageWindow(_ id: Int64) {
        messageWindows.open(messageID: id, viewModel: self)
    }

    func allowsRemoteImages(for message: StoredMessage) -> Bool {
        if allowedOnceMessageIDs.contains(message.id) {
            return true
        }
        return imagePolicyStore.isAlwaysAllowed(sender: message.fromAddress)
    }

    func shouldShowRemoteImageBanner(for message: StoredMessage, html: String?) -> Bool {
        guard !allowsRemoteImages(for: message) else { return false }
        return RemoteImagePolicyStore.containsRemoteImages(in: html)
    }

    func allowRemoteImagesOnce(messageID: Int64) {
        allowedOnceMessageIDs.insert(messageID)
    }

    func allowRemoteImagesAlways(sender: String?) {
        imagePolicyStore.allowAlways(sender: sender)
    }

    func parsedMessage(id: Int64) async -> MIMEMessage? {
        do {
            let raw = try await database.rawMessageData(id: id)
            return try MIME.parse(raw)
        } catch {
            return nil
        }
    }

    /// Unread message directly above wins. A read message above yields to the one below.
    private func focusedMessageID(afterDeleting ids: [Int64]) -> Int64? {
        let removed = Set(ids)
        guard let current = selectedMessageID, removed.contains(current),
              let index = messages.firstIndex(where: { $0.id == current })
        else {
            return nil
        }
        let above = messages[..<index].last { !removed.contains($0.id) }
        let below = messages[(index + 1)...].first { !removed.contains($0.id) }
        if let above, !above.isRead {
            return above.id
        }
        return below?.id ?? above?.id
    }

    /// The next message that stays in the list, or the previous one when the open message was last.
    private func neighborID(afterRemoving ids: [Int64]) -> Int64? {
        let removed = Set(ids)
        guard let current = selectedMessageID, removed.contains(current),
              let index = messages.firstIndex(where: { $0.id == current })
        else {
            return nil
        }
        if let next = messages[(index + 1)...].first(where: { !removed.contains($0.id) }) {
            return next.id
        }
        return messages[..<index].last { !removed.contains($0.id) }?.id
    }

    private func revealMessage(_ id: Int64?) async {
        guard selectedMessageID == nil, let id, messages.contains(where: { $0.id == id }) else { return }
        await selectMessage(id)
    }
}
