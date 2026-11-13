import Foundation

struct IMAPCopyResult: Equatable, Sendable {
    var uidValidity: String
    var source: [String]
    var destination: [String]
}

extension IMAPParser {
    static func copyUID(in text: String) -> IMAPCopyResult? {
        let upper = text.uppercased()
        guard let range = upper.range(of: "COPYUID") else { return nil }
        let tokens = text[range.upperBound...].split { $0 == " " || $0 == "]" }.map(String.init)
        guard tokens.count >= 3, tokens[0].allSatisfy(\.isNumber) else { return nil }
        let source = expandUIDSet(tokens[1])
        let destination = expandUIDSet(tokens[2])
        guard !source.isEmpty, source.count == destination.count else { return nil }
        return IMAPCopyResult(uidValidity: tokens[0], source: source, destination: destination)
    }

    static func expandUIDSet(_ set: String) -> [String] {
        var uids: [String] = []
        for part in set.split(separator: ",") {
            let bounds = part.split(separator: ":")
            if bounds.count == 2, let start = Int(bounds[0]), let end = Int(bounds[1]), end >= start,
               end - start < 10000
            {
                uids.append(contentsOf: (start ... end).map(String.init))
            } else if bounds.count == 1, Int(bounds[0]) != nil {
                uids.append(String(bounds[0]))
            }
        }
        return uids
    }
}
