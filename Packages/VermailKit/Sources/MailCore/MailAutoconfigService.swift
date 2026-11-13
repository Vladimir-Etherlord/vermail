import Foundation

public actor MailAutoconfigService {
    public typealias DataLoader = @Sendable (URL) async throws -> (Data, URLResponse)

    private let loadData: DataLoader

    public init(loadData: @escaping DataLoader = { try await URLSession.shared.data(from: $0) }) {
        self.loadData = loadData
    }

    public func configure(
        emailAddress: String,
        preferredIncoming: IncomingProtocol = .pop3
    ) async throws -> MailAutoconfigResult? {
        let domain = try emailDomain(from: emailAddress)

        if let preset = MailProviderPresets.preset(forDomain: domain) {
            let candidates = orderedCandidates(
                [preset.incoming, preset.imap],
                preferredIncoming: preferredIncoming
            )
            return MailAutoconfigResult(
                source: .preset,
                domain: domain,
                incomingCandidates: candidates,
                outgoing: preset.outgoing
            )
        }

        let url = URL(string: "https://autoconfig.thunderbird.net/v1.1/\(domain)")!
        let (data, response) = try await loadData(url)
        guard let http = response as? HTTPURLResponse else {
            throw MailAutoconfigError.invalidHTTPResponse
        }

        if http.statusCode == 404 {
            return nil
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw MailAutoconfigError.badHTTPStatus(http.statusCode)
        }

        let parsed = try ISPDBAutoconfigParser.parse(data)
        let candidates = orderedCandidates(parsed.incoming, preferredIncoming: preferredIncoming)
        if candidates.isEmpty, parsed.outgoing == nil {
            return nil
        }

        return MailAutoconfigResult(
            source: .ispdb,
            domain: domain,
            incomingCandidates: candidates,
            outgoing: parsed.outgoing
        )
    }

    private func emailDomain(from emailAddress: String) throws -> String {
        let trimmed = emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "@", maxSplits: 1)
        guard parts.count == 2, !parts[1].isEmpty else {
            throw MailAutoconfigError.invalidEmailAddress(emailAddress)
        }
        return String(parts[1]).lowercased()
    }

    private func orderedCandidates(
        _ incoming: [IncomingServerSettings],
        preferredIncoming: IncomingProtocol
    ) -> [IncomingServerSettings] {
        let preferred = incoming.filter { $0.protocolKind == preferredIncoming }
        let other = incoming.filter { $0.protocolKind != preferredIncoming }
        return preferred + other
    }
}
