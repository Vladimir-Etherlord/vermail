import MailCore
import MailStorage
import MIMEKit

enum ComposeSessionFactory {
    struct Context {
        var accounts: [MailAccount]
        var selectedMailbox: Mailbox
        var selectedMessage: StoredMessage?
        var parsedMessage: MIMEMessage?
        var database: MailDatabase
        var identityStore: ComposeIdentityStore
        var sendService: MailSendService
    }

    @MainActor
    static func make(request: ComposeRequest, context: Context) -> ComposeViewModel? {
        let enabled = context.accounts.filter(\.isEnabled)
        guard !enabled.isEmpty, let identities = try? context.identityStore.identities(for: enabled),
              !identities.isEmpty
        else {
            return nil
        }

        let account = accountForRequest(
            request,
            enabled: enabled,
            mailbox: context.selectedMailbox,
            message: context.selectedMessage
        )
        guard let account, let identity = identityFor(
            account: account,
            identities: identities,
            message: context.selectedMessage,
            parsed: context.parsedMessage,
            request: request
        ) else {
            return nil
        }

        let signature = (try? context.identityStore.signature(for: account.id)) ?? ""
        let draft = draftFor(
            request: request,
            account: account,
            identity: identity,
            identities: identities,
            source: context.selectedMessage.map { Source(message: $0, parsed: context.parsedMessage) }
        )
        guard let draft else { return nil }

        return ComposeViewModel(
            draft: draft,
            accounts: enabled,
            identities: identities,
            signature: signature,
            database: context.database,
            sendService: context.sendService,
            identityStore: context.identityStore
        )
    }

    private static func accountForRequest(
        _ request: ComposeRequest,
        enabled: [MailAccount],
        mailbox: Mailbox,
        message: StoredMessage?
    ) -> MailAccount? {
        switch request {
        case .newMessage:
            if case let .account(accountID) = mailbox.scope,
               let match = enabled.first(where: { $0.id == accountID })
            {
                return match
            }
            return enabled.first
        case .reply, .replyAll, .forward, .editDraft:
            guard let message else { return nil }
            return enabled.first { $0.id == message.accountID }
        }
    }

    private static func identityFor(
        account: MailAccount,
        identities: [MailIdentity],
        message: StoredMessage?,
        parsed: MIMEMessage?,
        request: ComposeRequest
    ) -> MailIdentity? {
        let matches = identities.filter { $0.accountID == account.id }
        guard request == .editDraft, let message else {
            return matches.first
        }
        let original = ComposeMessageBuilder.original(stored: message, parsed: parsed)
        guard let from = original.from, let email = ComposeMessageBuilder.emailAddress(in: from) else {
            return matches.first
        }
        return matches.first { $0.emailAddress.caseInsensitiveCompare(email) == .orderedSame } ?? matches.first
    }

    private struct Source {
        var message: StoredMessage
        var parsed: MIMEMessage?
    }

    private static func draftFor(
        request: ComposeRequest,
        account: MailAccount,
        identity: MailIdentity,
        identities: [MailIdentity],
        source: Source?
    ) -> ComposeDraft? {
        switch request {
        case .newMessage:
            ComposeMessageBuilder.newDraft(account: account, identity: identity)
        case .reply, .replyAll, .forward, .editDraft:
            draftFromExisting(
                request: request,
                account: account,
                identity: identity,
                identities: identities,
                source: source
            )
        }
    }

    private static func draftFromExisting(
        request: ComposeRequest,
        account: MailAccount,
        identity: MailIdentity,
        identities: [MailIdentity],
        source: Source?
    ) -> ComposeDraft? {
        guard let source else { return nil }
        let original = ComposeMessageBuilder.original(stored: source.message, parsed: source.parsed)
        switch request {
        case .reply:
            return ComposeMessageBuilder.reply(to: original, identity: identity)
        case .replyAll:
            let own = Set(identities.filter { $0.accountID == account.id }.map { $0.emailAddress.lowercased() })
            return ComposeMessageBuilder.replyAll(to: original, identity: identity, ownAddresses: own)
        case .forward:
            return ComposeMessageBuilder.forward(original: original, identity: identity)
        case .editDraft:
            return ComposeMessageBuilder.edit(original: original, identity: identity)
        case .newMessage:
            return nil
        }
    }
}
