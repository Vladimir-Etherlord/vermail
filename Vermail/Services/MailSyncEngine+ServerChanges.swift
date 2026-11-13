import Foundation
import MailCore
import MailStorage

extension MailSyncEngine {
    func setMessagesRead(_ isRead: Bool, ids: [Int64], accounts: [MailAccount]) async throws {
        try await MailServerChanges(engine: self).setRead(isRead, ids: ids, accounts: accounts)
    }

    func moveMessages(ids: [Int64], to folder: MailFolderKind, accounts: [MailAccount]) async throws {
        try await MailServerChanges(engine: self).move(ids: ids, to: folder, accounts: accounts)
    }

    func deleteMessages(ids: [Int64], permanently: Bool, accounts: [MailAccount]) async throws {
        try await MailServerChanges(engine: self).delete(ids: ids, permanently: permanently, accounts: accounts)
    }
}

/// Applies read, move, and delete changes. IMAP accounts are updated on the server first.
struct MailServerChanges {
    var engine: MailSyncEngine

    func setRead(_ isRead: Bool, ids: [Int64], accounts: [MailAccount]) async throws {
        try await change(ids, accounts: accounts) { account, messages in
            if writesToServer(account) {
                try await perform(account) { fetcher in
                    try await fetcher.setRead(isRead, refs: refs(from: messages))
                }
            }
            try await engine.database.setRead(isRead, messageIDs: messages.map(\.id))
        }
    }

    func move(ids: [Int64], to folder: MailFolderKind, accounts: [MailAccount]) async throws {
        try await change(ids, accounts: accounts) { account, messages in
            let moving = messages.filter { $0.folder != folder }
            guard !moving.isEmpty else { return }
            if writesToServer(account) {
                try await moveOnServer(moving, to: folder, account: account)
            } else {
                try await engine.database.moveMessages(ids: moving.map(\.id), to: folder)
            }
        }
    }

    func delete(ids: [Int64], permanently: Bool, accounts: [MailAccount]) async throws {
        if permanently {
            try await expunge(ids, accounts: accounts)
        } else {
            try await move(ids: ids, to: .trash, accounts: accounts)
        }
    }

    private func expunge(_ ids: [Int64], accounts: [MailAccount]) async throws {
        try await change(ids, accounts: accounts) { account, messages in
            if writesToServer(account) {
                try await perform(account) { fetcher in
                    try await fetcher.deleteMessages(refs(from: messages))
                }
            }
            try await engine.database.deleteMessages(ids: messages.map(\.id))
        }
    }

    private func moveOnServer(
        _ messages: [StoredMessage],
        to folder: MailFolderKind,
        account: MailAccount
    ) async throws {
        try await perform(account) { fetcher in
            let mailboxes = try await fetcher.remoteMailboxes()
            guard let mailbox = mailboxes.first(where: { $0.folder == folder }) else {
                throw MailSyncEngineError.server(
                    String(localized: "This account has no matching mailbox on the server.")
                )
            }
            let moved = try await fetcher.moveMessages(refs(from: messages), to: mailbox)
            try await remember(moved, folder: folder, messages: messages)
        }
    }

    private func remember(
        _ moved: [RemoteMessageMove],
        folder: MailFolderKind,
        messages: [StoredMessage]
    ) async throws {
        let bySource = Dictionary(uniqueKeysWithValues: messages.map { ($0.remoteUID, $0.id) })
        for change in moved {
            guard let id = bySource[change.sourceUID] else { continue }
            try await engine.database.relocateMessage(id: id, remoteUID: change.destinationUID, folder: folder)
        }
    }

    private func change(
        _ ids: [Int64],
        accounts: [MailAccount],
        body: (MailAccount, [StoredMessage]) async throws -> Void
    ) async throws {
        let stored = try await engine.database.messages(withIDs: ids)
        let byAccount = Dictionary(grouping: stored, by: \.accountID)
        var failure: Error?
        for account in accounts where byAccount[account.id]?.isEmpty == false {
            do {
                try await body(account, byAccount[account.id] ?? [])
            } catch {
                failure = MailSyncEngineError.presenting(error)
            }
        }
        if let failure {
            throw failure
        }
    }

    private func perform(
        _ account: MailAccount,
        _ body: (any MailFetching) async throws -> Void
    ) async throws {
        let (fetcher, cleanup) = try await engine.fetcherFactory.makeFetcher(
            for: account,
            secretStore: engine.secretStore
        )
        do {
            try await body(fetcher)
            await cleanup()
        } catch {
            await cleanup()
            throw error
        }
    }

    private func writesToServer(_ account: MailAccount) -> Bool {
        account.isEnabled && account.incomingProtocol == .imap
    }

    private func refs(from messages: [StoredMessage]) -> [RemoteMessageRef] {
        messages.map { RemoteMessageRef(uid: $0.remoteUID, size: $0.sizeBytes, isRead: $0.isRead) }
    }
}
