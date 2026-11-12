import Foundation

/// What the user is looking at: a folder across all accounts or a folder of one account.
public struct Mailbox: Hashable, Codable, Sendable {
    public enum Scope: Hashable, Codable, Sendable {
        /// Accounts with `isIncludedInUnifiedFolders` enabled.
        case unified
        case account(MailAccount.ID)
    }

    public var folder: MailFolderKind
    public var scope: Scope

    public init(folder: MailFolderKind, scope: Scope = .unified) {
        self.folder = folder
        self.scope = scope
    }

    public func includes(_ account: MailAccount) -> Bool {
        switch scope {
        case .unified: account.isIncludedInUnifiedFolders
        case let .account(id): account.id == id
        }
    }
}
