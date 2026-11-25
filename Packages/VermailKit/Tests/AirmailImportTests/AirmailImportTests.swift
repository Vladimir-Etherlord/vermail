import Foundation
import GRDB
import MailCore
import MailStorage
import MIMEKit
import Testing
@testable import AirmailImport

private struct SampleDone: Error {}

struct AirmailImportTests {
    @Test func importsOnlyMessagesMissingFromVermail() async throws {
        let fixture = try await AirmailFixture.make()
        defer { fixture.remove() }

        let dryRun = try await fixture.run(dryRun: true)
        #expect(dryRun.imported == 3)
        #expect(try await fixture.messageCount() == 1)

        let report = try await fixture.run(dryRun: false)
        #expect(report.scanned == 5)
        #expect(report.imported == 3)
        #expect(report.alreadyPresent == 1)
        #expect(report.skippedEmpty == 1)
        #expect(report.failed == 0)
        try await fixture.expectImportedMessages()

        let again = try await fixture.run(dryRun: false)
        #expect(again.imported == 0)
        #expect(again.alreadyPresent == 4)
        #expect(again.skippedEmpty == 1)
    }

    @Test func commandRejectsUnknownArguments() async {
        let code = await AirmailImportCommand.run(["airmail-import", "--bogus"])
        #expect(code == 1)
        let help = await AirmailImportCommand.run(["airmail-import", "--help"])
        #expect(help == 0)
    }
}

private struct AirmailFixture {
    var root: URL
    var account: MailAccount

    var airmail: URL {
        root.appending(path: "Airmail", directoryHint: .isDirectory)
    }

    var vermail: URL {
        root.appending(path: "Vermail", directoryHint: .isDirectory)
    }

    static func make() async throws -> AirmailFixture {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "vermail-airmail-\(UUID().uuidString)", directoryHint: .isDirectory)
        let fixture = try AirmailFixture(root: root, account: sampleAccount())
        try FileManager.default.createDirectory(at: fixture.airmail, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fixture.vermail, withIntermediateDirectories: true)
        try writeAirmail(at: fixture.airmail)
        try writeAccounts(fixture.account, to: fixture.vermail)
        try await seedKnownMessage(account: fixture.account, root: fixture.vermail)
        return fixture
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func run(dryRun: Bool) async throws -> AirmailImportReport {
        try await AirmailImportCommand.execute(AirmailImportOptions(
            airmailRoot: airmail,
            vermailRoot: vermail,
            dryRun: dryRun
        ))
    }

    func messageCount() async throws -> Int {
        try await database().allMessageRefs().count
    }

    func expectImportedMessages() async throws {
        let database = try database()
        let inbox = try await database.messages(in: Mailbox(folder: .inbox), accounts: [account])
        let drafts = try await database.messages(in: Mailbox(folder: .drafts), accounts: [account])
        try await expectHello(in: inbox, database: database)
        try await expectFile(in: inbox, database: database)
        try expectDraft(drafts)
        try await expectServerUID(database, account: account)
    }

    private func database() throws -> MailDatabase {
        try MailDatabase(rootDirectory: vermail)
    }
}

private func sampleAccount() throws -> MailAccount {
    try MailAccount(
        id: #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")),
        displayName: "Ada",
        emailAddress: "ada@example.com",
        incomingProtocol: .pop3
    )
}

private func expectHello(in inbox: [StoredMessage], database: MailDatabase) async throws {
    let hello = try #require(inbox.first { $0.subject == "Привет" })
    #expect(hello.remoteUID.hasPrefix("airmail:Message_0_1_50000:"))
    #expect(hello.fromAddress?.contains("ada@example.com") == true)
    #expect(hello.snippet == "Hello there")
    #expect(hello.receivedAt == Date(timeIntervalSince1970: 1_763_000_000))
    #expect(hello.isRead)
    let parsed = try await MIME.parse(database.rawMessageData(id: hello.id))
    #expect(parsed.plainBody == "Здравствуйте")
    #expect(parsed.subject == "Привет")
    let cc = parsed.headers.first { $0.name.caseInsensitiveCompare("Cc") == .orderedSame }
    #expect(cc?.value.contains("cara@example.com") == true)
}

private func expectFile(in inbox: [StoredMessage], database: MailDatabase) async throws {
    let file = try #require(inbox.first { $0.subject == "File" })
    #expect(file.hasAttachments)
    let parsed = try await MIME.parse(database.rawMessageData(id: file.id))
    #expect(parsed.plainBody?.contains("See file") == true)
    #expect(parsed.plainBody?.contains("WRONG") != true)
    #expect(parsed.attachments.count == 1)
}

private func expectDraft(_ drafts: [StoredMessage]) throws {
    let draft = try #require(drafts.first)
    #expect(draft.subject == "Draft note")
    #expect(!draft.isRead)
    #expect(drafts.count == 1)
}

private func expectServerUID(_ database: MailDatabase, account: MailAccount) async throws {
    let plan = try await database.pop3SyncPlan(
        accountID: account.id,
        serverRefs: [RemoteMessageRef(uid: "uidl-179209330164", size: 20, isRead: true)]
    )
    #expect(plan.toDownload.isEmpty)
    #expect(plan.alreadyKnown.map(\.uid) == ["uidl-179209330164"])
}

struct AirmailLiveSampleTests {
    @Test func twoLiveMessagesBecomeHTML() async throws {
        let root = AirmailLocations.airmailRoot(override: nil)
        guard FileManager.default.isReadableFile(atPath: root.fileSystemPath) else { return }
        let library = AirmailLibrary(root: root)
        var accepted = 0
        var sawRecent = false
        do {
            try await library.forEachLetter { letter in
                let parsed = try MIME.parse(letter.rawSource)
                guard let html = parsed.htmlBody, html.first == "<" else { return }
                let year = letter.receivedAt.map {
                    Calendar(identifier: .gregorian).component(.year, from: $0)
                }
                let intact = !html.hasPrefix("H4sI") && year.map { (2002 ... 2026).contains($0) } == true
                #expect(intact)
                accepted += 1
                if year == 2026 {
                    sawRecent = true
                }
                if accepted >= 2, sawRecent {
                    throw SampleDone()
                }
            }
        } catch is SampleDone {}
        #expect(accepted >= 2)
        #expect(sawRecent)
    }

    @Test func twoLiveMessagesKeepAttachments() async throws {
        let root = AirmailLocations.airmailRoot(override: nil)
        guard FileManager.default.isReadableFile(atPath: root.fileSystemPath) else { return }
        let library = AirmailLibrary(root: root)
        var accepted = 0
        var sawReport = false
        do {
            try await library.forEachLetter { letter in
                guard letter.hasAttachments else { return }
                let parsed = try MIME.parse(letter.rawSource)
                let intact = !parsed.attachments.isEmpty && parsed.attachments.allSatisfy { part in
                    !part.data.isEmpty && part.filename?.isEmpty == false
                }
                #expect(intact)
                if parsed.attachments.contains(where: { part in
                    part.data.count == 94540 && part.filename?.lowercased().hasSuffix(".html") == true
                }) {
                    sawReport = true
                }
                accepted += 1
                if accepted >= 2, sawReport {
                    throw SampleDone()
                }
            }
        } catch is SampleDone {}
        #expect(accepted >= 2)
        #expect(sawReport)
    }
}

private func writeAccounts(_ account: MailAccount, to root: URL) throws {
    let data = try JSONEncoder().encode([account])
    try data.write(to: root.appending(path: "accounts.json"))
}

private func seedKnownMessage(account: MailAccount, root: URL) async throws {
    let database = try MailDatabase(rootDirectory: root)
    _ = try await database.upsertMessage(StoredMessageInput(
        accountID: account.id,
        remoteUID: "179200000001",
        folder: .inbox,
        subject: "Old",
        fromAddress: "ada@example.com",
        toAddresses: [],
        snippet: "Hi",
        receivedAt: Date(timeIntervalSince1970: 1_700_000_000),
        isRead: true,
        rawSource: Data("From: ada@example.com\r\nMessage-ID: <Known@Example.com>\r\nSubject: Old\r\n\r\nHi\r\n".utf8)
    ))
}
