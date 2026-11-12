import MailCore
import MailTransport

public enum POP3 {
    public static let defaultPort = 110
    public static let defaultSecurePort = 995

    public static func defaultPort(for security: ConnectionSecurity) -> Int {
        security == .ssl ? defaultSecurePort : defaultPort
    }
}
