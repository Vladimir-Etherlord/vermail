import Foundation

enum ISPDBAutoconfigParser {
    struct Result {
        var incoming: [IncomingServerSettings]
        var outgoing: OutgoingServerSettings?
    }

    static func parse(_ data: Data) throws -> Result {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw MailAutoconfigError.malformedXML
        }
        return Result(incoming: delegate.incoming, outgoing: delegate.outgoing)
    }

    private enum SocketType: String {
        case ssl = "SSL"
        case startTLS = "STARTTLS"
        case plain
    }

    private struct IncomingDraft {
        var protocolType: IncomingProtocol?
        var host = ""
        var port: Int?
        var security: ServerSecurity = .none
        var authentication: ServerAuthenticationMethod = .userPassword
    }

    private struct OutgoingDraft {
        var host = ""
        var port: Int?
        var security: ServerSecurity = .none
        var authentication: ServerAuthenticationMethod = .userPassword
        var requiresAuthentication = true
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var incoming: [IncomingServerSettings] = []
        var outgoing: OutgoingServerSettings?

        private var currentPath: [String] = []
        private var currentText = ""
        private var incomingDraft: IncomingDraft?
        private var outgoingDraft: OutgoingDraft?

        func parser(
            _: XMLParser,
            didStartElement elementName: String,
            namespaceURI _: String?,
            qualifiedName _: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            currentPath.append(elementName)
            currentText = ""

            if elementName == "incomingServer" {
                var draft = IncomingDraft()
                if let type = attributeDict["type"]?.lowercased() {
                    draft.protocolType = type == "imap" ? .imap : type == "pop3" ? .pop3 : nil
                }
                incomingDraft = draft
            }

            if elementName == "outgoingServer" {
                outgoingDraft = OutgoingDraft()
            }
        }

        func parser(_: XMLParser, foundCharacters string: String) {
            currentText += string
        }

        func parser(
            _: XMLParser,
            didEndElement elementName: String,
            namespaceURI _: String?,
            qualifiedName _: String?
        ) {
            let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            updateIncomingDraft(with: value)
            updateOutgoingDraft(with: value)
            finalizeServerIfNeeded(elementName: elementName)

            _ = currentPath.popLast()
            currentText = ""
        }

        private func updateIncomingDraft(with value: String) {
            switch currentPath.suffix(2) {
            case ["incomingServer", "hostname"] where !value.isEmpty:
                incomingDraft?.host = value
            case ["incomingServer", "port"]:
                if let port = Int(value) {
                    incomingDraft?.port = port
                }
            case ["incomingServer", "socketType"] where !value.isEmpty:
                incomingDraft?.security = mapSocketType(value)
            case ["incomingServer", "authentication"] where !value.isEmpty:
                incomingDraft?.authentication = mapAuthentication(value)
            default:
                break
            }
        }

        private func updateOutgoingDraft(with value: String) {
            switch currentPath.suffix(2) {
            case ["outgoingServer", "hostname"] where !value.isEmpty:
                outgoingDraft?.host = value
            case ["outgoingServer", "port"]:
                if let port = Int(value) {
                    outgoingDraft?.port = port
                }
            case ["outgoingServer", "socketType"] where !value.isEmpty:
                outgoingDraft?.security = mapSocketType(value)
            case ["outgoingServer", "authentication"] where !value.isEmpty:
                outgoingDraft?.authentication = mapAuthentication(value)
                outgoingDraft?.requiresAuthentication = value.lowercased() != "none"
            default:
                break
            }
        }

        private func finalizeServerIfNeeded(elementName: String) {
            if elementName == "incomingServer", let draft = incomingDraft {
                if let settings = buildIncoming(from: draft) {
                    incoming.append(settings)
                }
                incomingDraft = nil
            }

            if elementName == "outgoingServer", let draft = outgoingDraft {
                if let settings = buildOutgoing(from: draft) {
                    outgoing = settings
                }
                outgoingDraft = nil
            }
        }

        private func buildIncoming(from draft: IncomingDraft) -> IncomingServerSettings? {
            guard let protocolType = draft.protocolType,
                  !draft.host.isEmpty,
                  let port = draft.port
            else {
                return nil
            }
            return IncomingServerSettings(
                protocolKind: protocolType,
                host: draft.host,
                port: port,
                security: draft.security,
                authentication: draft.authentication
            )
        }

        private func buildOutgoing(from draft: OutgoingDraft) -> OutgoingServerSettings? {
            guard !draft.host.isEmpty, let port = draft.port else {
                return nil
            }
            return OutgoingServerSettings(
                host: draft.host,
                port: port,
                security: draft.security,
                authentication: draft.authentication,
                requiresAuthentication: draft.requiresAuthentication
            )
        }

        private func mapSocketType(_ raw: String) -> ServerSecurity {
            switch SocketType(rawValue: raw.uppercased()) {
            case .ssl: .ssl
            case .startTLS: .startTLS
            default: .none
            }
        }

        private func mapAuthentication(_ raw: String) -> ServerAuthenticationMethod {
            switch raw.lowercased() {
            case "password-cleartext": .userPassword
            case "password-encrypted": .cramMD5
            case "oauth2": .xoauth2
            case "none": .none
            case "client-ip-address": .none
            default: .userPassword
            }
        }
    }
}
