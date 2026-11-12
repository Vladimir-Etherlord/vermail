import Foundation

public enum TransportError: Error, Equatable, Sendable {
    case connectionFailed(String)
    case timeout
    case connectionClosed
    /// Handshake failed or the server certificate was rejected.
    case tlsFailed(String)
    case lineTooLong
    /// The server sent data before the TLS handshake started (STARTTLS response injection).
    case unexpectedDataBeforeTLS
}

extension TransportError {
    static func from(_ error: any Error) -> TransportError {
        if let error = error as? TransportError {
            return error
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch URLError.Code(rawValue: nsError.code) {
            case .timedOut:
                return .timeout
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
                 .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected,
                 .clientCertificateRequired:
                return .tlsFailed(nsError.localizedDescription)
            case .networkConnectionLost:
                return .connectionClosed
            default:
                break
            }
        }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(ETIMEDOUT) {
            return .timeout
        }
        if nsError.domain == NSOSStatusErrorDomain, (-9899 ... -9800).contains(nsError.code) {
            return .tlsFailed(nsError.localizedDescription)
        }
        return .connectionFailed(nsError.localizedDescription)
    }
}
