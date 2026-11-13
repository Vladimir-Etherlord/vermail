import Foundation
import MailCore
import Testing

struct MailAutoconfigTests {
    @Test func presetAutoconfigForMailRu() async throws {
        let service = MailAutoconfigService(loadData: { _ in
            Issue.record("Preset path must not call network")
            return (
                Data(),
                HTTPURLResponse(
                    url: URL(string: "https://example.com")!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        })

        let result = try await service.configure(emailAddress: "user@mail.ru")
        #expect(result?.source == .preset)
        #expect(result?.bestIncoming(preferred: .pop3)?.host == "pop.mail.ru")
        #expect(result?.bestIncoming(preferred: .imap)?.host == "imap.mail.ru")
        #expect(result?.outgoing?.host == "smtp.mail.ru")
    }

    @Test func ispdbAutoconfigParsesIncomingAndOutgoing() async throws {
        let xml = """
        <?xml version=\"1.0\"?>
        <clientConfig version=\"1.1\">
          <emailProvider id=\"example.com\">
            <incomingServer type=\"imap\">
              <hostname>imap.example.com</hostname>
              <port>993</port>
              <socketType>SSL</socketType>
              <authentication>password-cleartext</authentication>
            </incomingServer>
            <incomingServer type=\"pop3\">
              <hostname>pop.example.com</hostname>
              <port>995</port>
              <socketType>SSL</socketType>
              <authentication>password-cleartext</authentication>
            </incomingServer>
            <outgoingServer type=\"smtp\">
              <hostname>smtp.example.com</hostname>
              <port>587</port>
              <socketType>STARTTLS</socketType>
              <authentication>password-cleartext</authentication>
            </outgoingServer>
          </emailProvider>
        </clientConfig>
        """
        let service = MailAutoconfigService(loadData: { _ in
            (
                Data(xml.utf8),
                HTTPURLResponse(
                    url: URL(string: "https://example.com")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        })

        let result = try await service.configure(emailAddress: "dev@example.com", preferredIncoming: .pop3)
        #expect(result?.source == .ispdb)
        #expect(result?.bestIncoming(preferred: .pop3)?.host == "pop.example.com")
        #expect(result?.outgoing?.host == "smtp.example.com")
        #expect(result?.outgoing?.security == .startTLS)
    }

    @Test func ispdb404ReturnsNil() async throws {
        let service = MailAutoconfigService(loadData: { _ in
            (
                Data(),
                HTTPURLResponse(
                    url: URL(string: "https://example.com")!,
                    statusCode: 404,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        })

        let result = try await service.configure(emailAddress: "dev@example.com")
        #expect(result == nil)
    }

    @Test func invalidEmailThrows() async {
        let service = MailAutoconfigService()

        do {
            _ = try await service.configure(emailAddress: "not-an-email")
            #expect(Bool(false), "Invalid email must throw")
        } catch let error as MailAutoconfigError {
            if case .invalidEmailAddress = error {
                #expect(Bool(true))
            } else {
                #expect(Bool(false), "Unexpected error: \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected non-MailAutoconfigError: \(error)")
        }
    }
}
