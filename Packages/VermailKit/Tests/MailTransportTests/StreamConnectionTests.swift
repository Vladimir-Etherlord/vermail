import Foundation
import MailTransport
import os
import Testing

@Suite(.greenMail, .timeLimit(.minutes(1)))
struct StreamConnectionGreenMailTests {
    @Test func plainPOP3Greeting() async throws {
        let connection = StreamConnection(configuration: .init(host: "localhost", port: 3110, security: .none))
        try await connection.open()
        let greeting = try await connection.readLineString()
        await connection.close()
        #expect(greeting.hasPrefix("+OK"))
    }

    @Test func sslWithSelfSignedCertificateWhenAllowed() async throws {
        let connection = StreamConnection(configuration: .init(
            host: "localhost",
            port: 3995,
            security: .ssl,
            allowsInvalidCertificates: true
        ))
        try await connection.open()
        let greeting = try await connection.readLineString()
        try await connection.writeLine("QUIT")
        #expect(try await connection.readLineString().hasPrefix("+OK"))
        await connection.close()
        #expect(greeting.hasPrefix("+OK"))
    }

    @Test func sslRejectsSelfSignedCertificateByDefault() async throws {
        let connection = StreamConnection(configuration: .init(host: "localhost", port: 3995, security: .ssl))
        try await connection.open()
        let elapsed = await ContinuousClock().measure {
            await #expect {
                _ = try await connection.readLine()
            } throws: { error in
                if case .tlsFailed = error as? TransportError {
                    return true
                }
                return false
            }
        }
        await connection.close()
        #expect(elapsed < .seconds(5), "must fail on the handshake, not on the read timeout")
    }

    @Test func multilineSMTPResponse() async throws {
        let connection = StreamConnection(configuration: .init(host: "localhost", port: 3025, security: .none))
        try await connection.open()
        #expect(try await connection.readLineString().hasPrefix("220"))
        try await connection.writeLine("EHLO vermail.test")
        var lines: [String] = []
        repeat {
            try await lines.append(connection.readLineString())
        } while lines.last?.hasPrefix("250-") == true
        await connection.close()
        #expect(lines.last?.hasPrefix("250 ") == true)
    }

    @Test func sensitiveDataIsRedactedInLog() async throws {
        let events = OSAllocatedUnfairLock<[TrafficEvent]>(initialState: [])
        let connection = StreamConnection(
            configuration: .init(host: "localhost", port: 3110, security: .none),
            logger: { event in events.withLock { $0.append(event) } }
        )
        try await connection.open()
        _ = try await connection.readLine()
        try await connection.writeLine("USER test@localhost")
        _ = try await connection.readLine()
        try await connection.writeLine("PASS secret", sensitive: true)
        _ = try await connection.readLine()
        await connection.close()

        let sent = events.withLock { $0.filter { $0.direction == .sent }.map(\.text) }
        #expect(sent == ["USER test@localhost", "<redacted>"])
    }

    @Test func refusedConnectionFails() async throws {
        let connection = StreamConnection(configuration: .init(host: "localhost", port: 1, security: .none, timeout: 5))
        try await connection.open()
        await #expect(throws: TransportError.self) { _ = try await connection.readLine() }
        await connection.close()
    }
}

@Suite(.liveServers, .timeLimit(.minutes(1)))
struct StreamConnectionLiveTests {
    @Test func mailRuPOP3OverSSL() async throws {
        let connection = StreamConnection(configuration: .init(host: "pop.mail.ru", port: 995, security: .ssl))
        try await connection.open()
        let greeting = try await connection.readLineString()
        await connection.close()
        #expect(greeting.hasPrefix("+OK"))
    }

    @Test func mailRuSMTPWithSTARTTLS() async throws {
        let connection = StreamConnection(configuration: .init(host: "smtp.mail.ru", port: 587, security: .startTLS))
        try await connection.open()
        #expect(try await connection.readLineString().hasPrefix("220"))
        let capabilities = try await ehlo(connection)
        #expect(capabilities.contains { $0.contains("STARTTLS") })

        try await connection.writeLine("STARTTLS")
        #expect(try await connection.readLineString().hasPrefix("220"))
        try await connection.startTLS()

        let secureCapabilities = try await ehlo(connection)
        #expect(secureCapabilities.contains { $0.contains("AUTH") })
        await connection.close()
    }

    private func ehlo(_ connection: StreamConnection) async throws -> [String] {
        try await connection.writeLine("EHLO vermail.test")
        var lines: [String] = []
        repeat {
            try await lines.append(connection.readLineString())
        } while lines.last?.hasPrefix("250-") == true
        return lines
    }
}
