import Foundation

struct AirmailStoredFile: Equatable, Sendable {
    var filename: String
    var mimeType: String
    var data: Data
}

enum AirmailAttachments {
    static func files(messageID: String?, external: Data, inline: Data, directory: URL) -> [AirmailStoredFile] {
        guard let messageID, !messageID.isEmpty else { return [] }
        let entries = directoryEntries(directory.appendingPathComponent(messageID))
        guard !entries.isEmpty else { return [] }
        var used: Set<String> = []
        return (models(in: external) + models(in: inline)).compactMap { record in
            storedFile(record, entries: entries, used: &used)
        }
    }

    private static func storedFile(
        _ record: AirmailAttachmentRecord,
        entries: [URL],
        used: inout Set<String>
    ) -> AirmailStoredFile? {
        guard let url = locate(record, entries: entries), used.insert(url.path).inserted,
              let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return AirmailStoredFile(filename: filename(record, url: url), mimeType: mimeType(record.mimeType), data: data)
    }

    private static func locate(_ record: AirmailAttachmentRecord, entries: [URL]) -> URL? {
        for name in [record.fileName, record.pathBase].compactMap(\.self) where !name.isEmpty {
            if let match = entries.first(where: { sameName($0.lastPathComponent, name) }) {
                return match
            }
        }
        let matches = entries.filter { fileSize($0) == record.size }
        guard record.size > 0, matches.count == 1 else { return nil }
        return matches[0]
    }

    private static func directoryEntries(_ url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private static func filename(_ record: AirmailAttachmentRecord, url: URL) -> String {
        let preferred = record.fileName.flatMap { safeName($0) } ?? safeName(url.lastPathComponent)
        return preferred.isEmpty ? "attachment" : preferred
    }

    private static func safeName(_ value: String) -> String {
        let base = URL(fileURLWithPath: value).lastPathComponent
        let scalars = base.unicodeScalars.filter { scalar in
            scalar.value >= 32 && scalar != "\"" && scalar != "\\" && scalar != "/"
        }
        return String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func mimeType(_ value: String?) -> String {
        let token = value?.split(separator: ";").first.map(String.init) ?? ""
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let ascii = cleaned.unicodeScalars.allSatisfy { $0.isASCII && !$0.properties.isWhitespace && $0 != "\"" }
        guard cleaned.contains("/"), ascii else { return "application/octet-stream" }
        return cleaned
    }

    private static func sameName(_ lhs: String, _ rhs: String) -> Bool {
        lhs.precomposedStringWithCanonicalMapping == rhs.precomposedStringWithCanonicalMapping
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private static func models(in data: Data) -> [AirmailAttachmentRecord] {
        guard !data.isEmpty,
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let archive = plist as? NSDictionary,
              let top = archive["$top"] as? NSDictionary
        else {
            return []
        }
        let objects = array(archive["$objects"])
        guard !objects.isEmpty else { return [] }
        let root = resolve(top["root"] as Any, objects: objects)
        guard let dictionary = root as? NSDictionary else { return [] }
        return array(dictionary["NS.objects"]).compactMap { item in
            record(resolve(item, objects: objects), objects: objects)
        }
    }

    private static func record(_ value: Any, objects: [Any]) -> AirmailAttachmentRecord? {
        guard let dictionary = value as? NSDictionary else { return nil }
        return AirmailAttachmentRecord(
            fileName: text(dictionary["fileName"], objects: objects),
            pathBase: text(dictionary["path"], objects: objects).map { URL(fileURLWithPath: $0).lastPathComponent },
            mimeType: text(dictionary["contentype"], objects: objects),
            size: integer(resolve(dictionary["size"] as Any, objects: objects)) ?? 0
        )
    }

    private static func text(_ value: Any?, objects: [Any]) -> String? {
        guard let resolved = value.map({ resolve($0, objects: objects) }) else { return nil }
        let string = (resolved as? String) ?? (resolved as? NSString).map { $0 as String }
        let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func resolve(_ value: Any, objects: [Any], depth: Int = 0) -> Any {
        guard depth < 8, let index = uidIndex(value), objects.indices.contains(index) else { return value }
        return resolve(objects[index], objects: objects, depth: depth + 1)
    }

    private static func uidIndex(_ value: Any) -> Int? {
        if let dictionary = value as? NSDictionary {
            guard dictionary.count == 1 else { return nil }
            return integer(dictionary["CF$UID"]).map(Int.init)
        }
        if value is NSArray || value is NSString || value is NSNumber {
            return nil
        }
        let described = String(describing: value)
        guard described.contains("CFKeyedArchiverUID"),
              let range = described.range(of: #"value = [0-9]+"#, options: .regularExpression)
        else {
            return nil
        }
        return Int(described[range].split(separator: " ").last ?? "")
    }

    private static func array(_ value: Any?) -> [Any] {
        if let list = value as? [Any] {
            return list
        }
        if let list = value as? NSArray {
            return list.compactMap(\.self)
        }
        return []
    }

    private static func integer(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.int64Value
    }
}

private struct AirmailAttachmentRecord {
    var fileName: String?
    var pathBase: String?
    var mimeType: String?
    var size: Int64
}
