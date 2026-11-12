import Foundation
import os

/// `MailConnection` over `URLSessionStreamTask`. Unlike `NWConnection`, a stream task can switch
/// an established plain connection to TLS, which STARTTLS (SMTP) and STLS (POP3) require.
public actor StreamConnection: MailConnection {
    private let configuration: TransportConfiguration
    private let logger: TrafficLogger?
    private let trustDelegate: TrustDelegate
    private let session: URLSession
    private let task: URLSessionStreamTask
    private var buffer = LineBuffer()
    private var isOpen = false
    private var isSecure = false

    public init(configuration: TransportConfiguration, logger: TrafficLogger? = nil) {
        self.configuration = configuration
        self.logger = logger
        trustDelegate = TrustDelegate(allowsInvalidCertificates: configuration.allowsInvalidCertificates)
        session = URLSession(configuration: .ephemeral, delegate: trustDelegate, delegateQueue: nil)
        task = session.streamTask(withHostName: configuration.host, port: configuration.port)
    }

    public func open() async throws(TransportError) {
        guard !isOpen else { return }
        isOpen = true
        task.resume()
        if configuration.security == .ssl {
            task.startSecureConnection()
            isSecure = true
        }
    }

    public func readLine() async throws(TransportError) -> Data {
        while true {
            if let line = try buffer.nextLine() {
                logger?(TrafficEvent(direction: .received, text: String(decoding: line, as: UTF8.self)))
                return line
            }
            let (data, isAtEnd) = try await perform {
                try await task.readData(ofMinLength: 1, maxLength: 64 * 1024, timeout: configuration.timeout)
            }
            if let data, !data.isEmpty {
                buffer.append(data)
            } else if isAtEnd {
                throw .connectionClosed
            }
        }
    }

    public func write(_ data: Data, sensitive: Bool) async throws(TransportError) {
        if let logger {
            let text = sensitive ? "<redacted>" : String(decoding: data, as: UTF8.self)
            logger(TrafficEvent(direction: .sent, text: text.trimmingCharacters(in: .newlines)))
        }
        try await perform { try await task.write(data, timeout: configuration.timeout) }
    }

    public func startTLS() async throws(TransportError) {
        guard !isSecure else { return }
        guard buffer.isEmpty else { throw .unexpectedDataBeforeTLS }
        task.startSecureConnection()
        isSecure = true
    }

    public func close() async {
        task.cancel()
        session.invalidateAndCancel()
        isOpen = false
    }

    private func perform<T>(_ operation: () async throws -> T) async throws(TransportError) -> T {
        do {
            return try await operation()
        } catch {
            if let trustFailure = trustDelegate.trustFailure {
                throw .tlsFailed(trustFailure)
            }
            throw TransportError.from(error)
        }
    }
}

/// Evaluates server trust explicitly: with default handling a rejected certificate makes the stream task
/// hang until the read timeout instead of failing.
private final class TrustDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let allowsInvalidCertificates: Bool
    private let failure = OSAllocatedUnfairLock<String?>(initialState: nil)

    var trustFailure: String? {
        failure.withLock { $0 }
    }

    init(allowsInvalidCertificates: Bool) {
        self.allowsInvalidCertificates = allowsInvalidCertificates
    }

    func urlSession(
        _: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        evaluate(challenge)
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        evaluate(challenge)
    }

    private func evaluate(_ challenge: URLAuthenticationChallenge) -> (
        URLSession.AuthChallengeDisposition,
        URLCredential?
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else { return (.performDefaultHandling, nil) }

        var error: CFError?
        if allowsInvalidCertificates || SecTrustEvaluateWithError(trust, &error) {
            return (.useCredential, URLCredential(trust: trust))
        }
        let reason = error.map { CFErrorCopyDescription($0) as String } ?? "Server certificate is not trusted"
        failure.withLock { $0 = reason }
        return (.cancelAuthenticationChallenge, nil)
    }
}
