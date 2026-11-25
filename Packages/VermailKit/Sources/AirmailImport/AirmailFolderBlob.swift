import Foundation

struct AirmailFolderBinding: Equatable {
    var folderIDs: [Int64]
    var serverUID: String?
    var isRead: Bool?
}

enum AirmailFolderBlob {
    static func binding(from data: Data) -> AirmailFolderBinding {
        if data.isEmpty {
            return AirmailFolderBinding(folderIDs: [], serverUID: nil, isRead: nil)
        }
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
            let decoded = isKeyedArchive(plist) ? keyedArchiveBinding(plist) : binding(from: plist)
            if !decoded.folderIDs.isEmpty || decoded.serverUID != nil || decoded.isRead != nil {
                return decoded
            }
        }
        if let object = keyedObject(data) {
            let decoded = binding(from: object)
            if !decoded.folderIDs.isEmpty || decoded.serverUID != nil {
                return decoded
            }
        }
        return AirmailFolderBinding(folderIDs: packedIDs(data), serverUID: nil, isRead: nil)
    }

    static func binding(from object: Any) -> AirmailFolderBinding {
        guard let dictionary = object as? NSDictionary else {
            return AirmailFolderBinding(folderIDs: integerList(object), serverUID: nil, isRead: nil)
        }
        var ids: [Int64] = []
        var serverUID: String?
        for key in dictionary.allKeys {
            let folderID = integerValue(key)
            if let folderID {
                ids.append(folderID)
            }
            if serverUID == nil {
                serverUID = serverUIDValue(dictionary[key], folderID: folderID)
            }
        }
        if ids.isEmpty {
            ids = dictionary.allValues.flatMap { integerList($0) }
        }
        return AirmailFolderBinding(folderIDs: ids, serverUID: serverUID, isRead: nil)
    }

    /// Airmail stores `folder id -> UidFlags` in an `NSKeyedArchiver` blob. The value class does
    /// not unarchive, so the folder id and the seen bit are read from the archive objects.
    private static func keyedArchiveBinding(_ object: Any) -> AirmailFolderBinding {
        guard let archive = object as? NSDictionary,
              let top = archive["$top"] as? NSDictionary
        else {
            return AirmailFolderBinding(folderIDs: [], serverUID: nil, isRead: nil)
        }
        let objects = array(archive["$objects"])
        guard !objects.isEmpty else {
            return AirmailFolderBinding(folderIDs: [], serverUID: nil, isRead: nil)
        }
        let root = resolve(top["root"] as Any, objects: objects)
        guard let dictionary = root as? NSDictionary else {
            return AirmailFolderBinding(folderIDs: [], serverUID: nil, isRead: nil)
        }
        return binding(keys: array(dictionary["NS.keys"]), values: array(dictionary["NS.objects"]), objects: objects)
    }

    private static func binding(keys: [Any], values: [Any], objects: [Any]) -> AirmailFolderBinding {
        var ids: [Int64] = []
        var serverUID: String?
        var sawFlags = false
        var isRead = true
        for (key, value) in zip(keys, values) {
            let folderID = integerValue(resolve(key, objects: objects))
            let resolved = resolve(value, objects: objects)
            if let folderID {
                ids.append(folderID)
            }
            if serverUID == nil {
                serverUID = serverUIDValue(uidField(resolved), folderID: folderID)
            }
            if let flags = flagsValue(resolved) {
                sawFlags = true
                if (flags & 2) == 0 {
                    isRead = false
                }
            }
        }
        return AirmailFolderBinding(folderIDs: ids, serverUID: serverUID, isRead: sawFlags ? isRead : nil)
    }

    private static func resolve(_ value: Any, objects: [Any], depth: Int = 0) -> Any {
        guard depth < 8, let index = uidIndex(value), objects.indices.contains(index) else { return value }
        return resolve(objects[index], objects: objects, depth: depth + 1)
    }

    private static func uidIndex(_ value: Any) -> Int? {
        if let dictionary = value as? NSDictionary {
            guard dictionary.count == 1, let number = integerValue(dictionary["CF$UID"]) else { return nil }
            return Int(number)
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

    private static func uidField(_ value: Any) -> Any? {
        guard let dictionary = value as? NSDictionary else { return value }
        return dictionary["uid"] ?? value
    }

    private static func flagsValue(_ value: Any) -> Int64? {
        guard let dictionary = value as? NSDictionary else { return nil }
        return integerValue(dictionary["flags"])
    }

    private static func keyedObject(_ data: Data) -> Any? {
        try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data)
    }

    private static func isKeyedArchive(_ object: Any) -> Bool {
        guard let dictionary = object as? NSDictionary else { return false }
        return dictionary["$archiver"] != nil
    }

    private static func integerList(_ object: Any) -> [Int64] {
        if let value = integerValue(object) {
            return [value]
        }
        if let list = object as? [Any] {
            return list.flatMap { integerList($0) }
        }
        return []
    }

    private static func integerValue(_ value: Any?) -> Int64? {
        guard let value else { return nil }
        if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            return number.int64Value
        }
        if let text = value as? String {
            return Int64(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func serverUIDValue(_ value: Any?, folderID: Int64?) -> String? {
        let text: String? = if let string = value as? String {
            string
        } else if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            String(number.int64Value)
        } else {
            nil
        }
        guard var text else { return nil }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 8, text.unicodeScalars.allSatisfy(\.isASCII),
              text.unicodeScalars.allSatisfy({ !$0.properties.isWhitespace }) else { return nil }
        if let folderID, text == String(folderID) {
            return nil
        }
        return text
    }

    private static func packedIDs(_ data: Data) -> [Int64] {
        guard data.count >= 8, data.count.isMultiple(of: 8), data.count <= 64 else { return [] }
        var ids: [Int64] = []
        var offset = 0
        while offset < data.count {
            let value = data.subdata(in: offset ..< offset + 8).withUnsafeBytes { raw in
                raw.load(as: Int64.self)
            }
            if offset.isMultiple(of: 16), (1 ... 1_000_000).contains(value) {
                ids.append(value)
            }
            offset += 8
        }
        return ids
    }
}
