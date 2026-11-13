import Foundation

public enum OAuthProvider: String, CaseIterable, Codable, Sendable {
    case gmail
    case outlook
}

public struct OAuthConfiguration: Hashable, Codable, Sendable {
    public var provider: OAuthProvider
    public var authorizationEndpoint: URL
    public var tokenEndpoint: URL
    public var scopes: [String]
    public var recommendedIncomingAuth: ServerAuthenticationMethod
    public var recommendedOutgoingAuth: ServerAuthenticationMethod

    public init(
        provider: OAuthProvider,
        authorizationEndpoint: URL,
        tokenEndpoint: URL,
        scopes: [String],
        recommendedIncomingAuth: ServerAuthenticationMethod,
        recommendedOutgoingAuth: ServerAuthenticationMethod
    ) {
        self.provider = provider
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.scopes = scopes
        self.recommendedIncomingAuth = recommendedIncomingAuth
        self.recommendedOutgoingAuth = recommendedOutgoingAuth
    }
}

public enum OAuthConfigurationCatalog {
    public static let gmail = OAuthConfiguration(
        provider: .gmail,
        authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
        tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!,
        scopes: ["openid", "email", "https://mail.google.com/"],
        recommendedIncomingAuth: .xoauth2,
        recommendedOutgoingAuth: .xoauth2
    )

    public static let outlook = OAuthConfiguration(
        provider: .outlook,
        authorizationEndpoint: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!,
        tokenEndpoint: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!,
        scopes: [
            "offline_access",
            "email",
            "https://outlook.office.com/IMAP.AccessAsUser.All",
            "https://outlook.office.com/POP.AccessAsUser.All",
            "https://outlook.office.com/SMTP.Send",
        ],
        recommendedIncomingAuth: .xoauth2,
        recommendedOutgoingAuth: .xoauth2
    )

    public static func configuration(for provider: OAuthProvider) -> OAuthConfiguration {
        switch provider {
        case .gmail: gmail
        case .outlook: outlook
        }
    }

    public static func provider(forEmailAddress emailAddress: String) -> OAuthProvider? {
        guard let domainSub = emailAddress.split(separator: "@").last else {
            return nil
        }
        let domain = String(domainSub).lowercased()
        if ["gmail.com", "googlemail.com"].contains(domain) {
            return .gmail
        }
        if ["outlook.com", "hotmail.com", "live.com", "msn.com"].contains(domain) {
            return .outlook
        }
        return nil
    }

    public static func xoauth2Payload(emailAddress: String, accessToken: String) -> String {
        let payload = "user=\(emailAddress)\u{1}auth=Bearer \(accessToken)\u{1}\u{1}"
        return Data(payload.utf8).base64EncodedString()
    }
}
