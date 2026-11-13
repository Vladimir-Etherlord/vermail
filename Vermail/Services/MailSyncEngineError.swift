import Foundation
import IMAPKit
import POP3Kit

extension MailSyncEngineError {
    static func presenting(_ error: Error) -> Error {
        if let error = error as? IMAPError {
            return imap(error)
        }
        if let error = error as? POP3Error {
            return pop3(error)
        }
        return error
    }

    private static func imap(_ error: IMAPError) -> MailSyncEngineError {
        switch error {
        case .missingPassword, .missingOAuthToken:
            .missingCredentials
        case .notAuthenticated:
            .server(String(localized: "Sign in to the mail server before downloading messages."))
        case .startTLSUnavailable:
            .server(String(localized: "The server does not support STARTTLS."))
        case .messageNotFound:
            .server(String(localized: "The message is no longer on the server."))
        case let .serverError(text), let .invalidResponse(text):
            .server(text)
        }
    }

    private static func pop3(_ error: POP3Error) -> MailSyncEngineError {
        switch error {
        case .missingPassword, .missingOAuthToken, .missingAPOPChallenge:
            .missingCredentials
        case let .serverError(text), let .invalidResponse(text), let .invalidGreeting(text),
             let .authenticationFailed(text), let .messageNotFound(text):
            .server(text)
        }
    }
}
