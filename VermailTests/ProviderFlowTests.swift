import Darwin
import Foundation
import MailCore
import MailStorage
import Testing
@testable import Vermail

extension Trait where Self == ConditionTrait {
    static var greenMail: Self {
        .enabled(if: GreenMailProbe.isReachable(), "GreenMail is not accepting POP3 on port 3110")
    }
}

enum GreenMailProbe {
    static func isReachable(port: UInt16 = 3110) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else { return false }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.connect(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if connected == 0 {
            return true
        }
        guard errno == EINPROGRESS else { return false }

        var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
        guard poll(&pollDescriptor, 1, 200) > 0 else { return false }
        return pollDescriptor.revents & Int16(POLLOUT) != 0
    }
}

@Suite(.greenMail, .timeLimit(.minutes(2)))
struct ProviderFlowTests {
    @Test func appSendsAndReceivesAMessage() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "ProviderFlow-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let database = try MailDatabase(rootDirectory: root)
        let secrets = InMemorySecretStore()
        let account = greenMailAccount()
        await secrets.saveSecret("test", for: account.id, kind: .incomingPassword)
        await secrets.saveSecret("test", for: account.id, kind: .outgoingPassword)

        let marker = "VermailQA-\(UUID().uuidString)"
        let identity = MailIdentity(
            accountID: account.id,
            displayName: "Test",
            emailAddress: "test@localhost"
        )
        let sent = try await MailSendService(database: database, secretStore: secrets).send(
            draft: ComposeDraft(
                accountID: account.id,
                identityID: identity.id,
                to: ["test@localhost"],
                subject: marker,
                body: "Привет, проверка"
            ),
            account: account,
            identity: identity,
            signature: ""
        )
        #expect(sent.folder == .sent)

        let report = await MailSyncEngine(database: database, secretStore: secrets).syncAccounts([account])
        #expect(report.states[account.id] == .idle)

        let mailbox = Mailbox(folder: .inbox, scope: .unified)
        let inbox = try await database.messages(in: mailbox, accounts: [account])
        #expect(inbox.contains { $0.subject == marker })
        let found = try await database.searchMessages(query: "Привет", in: mailbox, accounts: [account])
        #expect(found.contains { $0.subject == marker })
    }

    private func greenMailAccount() -> MailAccount {
        MailAccount(
            displayName: "GreenMail",
            emailAddress: "test@localhost",
            incomingProtocol: .pop3,
            incomingServer: IncomingServerSettings(
                protocolKind: .pop3,
                host: "localhost",
                port: 3110,
                security: .none,
                authentication: .userPassword
            ),
            outgoingServer: OutgoingServerSettings(
                host: "localhost",
                port: 3025,
                security: .none,
                authentication: .userPassword
            ),
            details: AccountDetails(
                incomingUsername: "test@localhost",
                outgoingUsername: "test@localhost",
                leaveMailOnServer: true
            )
        )
    }
}
