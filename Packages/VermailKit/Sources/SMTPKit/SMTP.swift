import MailCore
import MailTransport

public enum SMTP {
    public static let defaultPort = 25
    public static let defaultSubmissionPort = 587
    public static let defaultSecurePort = 465

    public static func defaultPort(for security: ConnectionSecurity) -> Int {
        switch security {
        case .none: defaultPort
        case .startTLS: defaultSubmissionPort
        case .ssl: defaultSecurePort
        }
    }
}
