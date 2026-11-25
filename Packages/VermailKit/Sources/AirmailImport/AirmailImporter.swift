import Foundation
import MailCore
import MailStorage

struct AirmailImporter: Sendable {
    static func importMail(
        from library: AirmailLibrary,
        into database: MailDatabase,
        accounts: [MailAccount],
        accountEmail: String? = nil,
        dryRun: Bool = false
    ) async throws -> AirmailImportReport {
        let pair = try AirmailAccountPair.select(
            airmailEmails: library.accountEmails(),
            vermail: accounts,
            requested: accountEmail
        )
        var state = try await AirmailImportState(presence: AirmailPresence.load(from: database))
        try await library.forEachLetter { letter in
            guard AirmailLocations.sameEmail(letter.accountEmail, pair.airmailEmail) else { return }
            do {
                try await accept(letter, pair: pair, database: database, dryRun: dryRun, state: &state)
            } catch {
                state.report.failed += 1
            }
        }
        return state.report
    }
}

struct AirmailAccountPair {
    var airmailEmail: String
    var vermail: MailAccount

    static func select(airmailEmails: [String], vermail: [MailAccount], requested: String?) throws -> Self {
        let airmail = unique(airmailEmails)
        if vermail.isEmpty {
            throw AirmailImportError.noVermailAccounts("")
        }
        if let requested {
            return try requestedPair(requested, airmail: airmail, vermail: vermail)
        }
        return try matchedPair(airmail: airmail, vermail: vermail)
    }

    private static func requestedPair(
        _ requested: String,
        airmail: [String],
        vermail: [MailAccount]
    ) throws -> Self {
        guard let account = vermail.first(where: { AirmailLocations.sameEmail($0.emailAddress, requested) }) else {
            throw AirmailImportError.accountNotFound(requested)
        }
        if let email = airmail.first(where: { AirmailLocations.sameEmail($0, requested) }) {
            return Self(airmailEmail: email, vermail: account)
        }
        if airmail.count == 1, let email = airmail.first {
            return Self(airmailEmail: email, vermail: account)
        }
        throw AirmailImportError.accountNotFound(requested)
    }

    private static func matchedPair(airmail: [String], vermail: [MailAccount]) throws -> Self {
        let matches = vermail.filter { account in
            airmail.contains { AirmailLocations.sameEmail($0, account.emailAddress) }
        }
        if matches.count == 1, let account = matches.first,
           let email = airmail.first(where: { AirmailLocations.sameEmail($0, account.emailAddress) })
        {
            return Self(airmailEmail: email, vermail: account)
        }
        if airmail.count == 1, vermail.count == 1, let email = airmail.first, let account = vermail.first {
            return Self(airmailEmail: email, vermail: account)
        }
        throw AirmailImportError.ambiguousAccounts
    }

    private static func unique(_ emails: [String]) -> [String] {
        var seen = Set<String>()
        return emails.filter { seen.insert($0.lowercased()).inserted }
    }
}

private struct AirmailImportState {
    var presence: AirmailPresence
    var report = AirmailImportReport()
}

private struct AirmailPresence {
    var remoteUIDs: Set<String>
    var messageIDs: Set<String>

    static func load(from database: MailDatabase) async throws -> AirmailPresence {
        let refs = try await database.allMessageRefs()
        var messageIDs = Set<String>()
        for ref in refs where !ref.remoteUID.hasPrefix(AirmailMessageID.remotePrefix) {
            guard let data = try? await database.rawMessageData(id: ref.id),
                  let messageID = AirmailMessageID.headerValue(in: data)
            else {
                continue
            }
            messageIDs.insert(messageID)
        }
        return try await AirmailPresence(remoteUIDs: database.knownRemoteUIDs(), messageIDs: messageIDs)
    }
}

private func accept(
    _ letter: AirmailLetter,
    pair: AirmailAccountPair,
    database: MailDatabase,
    dryRun: Bool,
    state: inout AirmailImportState
) async throws {
    state.report.scanned += 1
    if letter.isEmpty {
        state.report.skippedEmpty += 1
        return
    }
    if isPresent(letter, in: state.presence) {
        if !dryRun, state.presence.remoteUIDs.contains(letter.remoteUID) {
            try await store(letter, pair: pair, database: database)
        }
        state.report.alreadyPresent += 1
        return
    }
    if !dryRun {
        try await store(letter, pair: pair, database: database)
    }
    remember(letter, in: &state.presence)
    state.report.imported += 1
}

private func isPresent(_ letter: AirmailLetter, in presence: AirmailPresence) -> Bool {
    if presence.remoteUIDs.contains(letter.remoteUID) {
        return true
    }
    if let serverUID = letter.serverUID, presence.remoteUIDs.contains(serverUID) {
        return true
    }
    if let messageID = letter.messageID, presence.messageIDs.contains(messageID) {
        return true
    }
    return false
}

private func remember(_ letter: AirmailLetter, in presence: inout AirmailPresence) {
    presence.remoteUIDs.insert(letter.remoteUID)
    if let serverUID = letter.serverUID {
        presence.remoteUIDs.insert(serverUID)
    }
    if let messageID = letter.messageID {
        presence.messageIDs.insert(messageID)
    }
}

private func store(_ letter: AirmailLetter, pair: AirmailAccountPair, database: MailDatabase) async throws {
    let from = letter.fromAddress.isEmpty ? nil : letter.fromAddress
    let stored = try await database.upsertMessage(StoredMessageInput(
        accountID: pair.vermail.id,
        remoteUID: letter.remoteUID,
        folder: letter.folder,
        subject: letter.subject.isEmpty ? nil : letter.subject,
        fromAddress: from,
        toAddresses: letter.toAddresses,
        snippet: letter.snippet,
        receivedAt: letter.receivedAt,
        isRead: letter.isRead,
        hasAttachments: letter.hasAttachments,
        rawSource: letter.rawSource
    ))
    let leavesMail = pair.vermail.details?.leaveMailOnServer ?? true
    guard leavesMail, let serverUID = letter.serverUID else { return }
    try await database.noteServerUID(serverUID, accountID: pair.vermail.id, messageID: stored.id)
}
