import Foundation
import MailCore

enum AirmailLocations {
    static func airmailRoot(override: URL?) -> URL {
        if let override {
            return override
        }
        let group = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Group Containers/2E337YPCZY.airmail", directoryHint: .isDirectory)
            .appending(path: "Library/Application Support", directoryHint: .isDirectory)
        let bundles = ["it.bloop.airmail2", "it.bloop.airmail", "it.bloop.airmail.beta11"]
        for bundle in bundles {
            let candidate = group.appending(path: bundle).appending(path: "Airmail", directoryHint: .isDirectory)
            if FileManager.default.fileExists(atPath: candidate.fileSystemPath) {
                return candidate
            }
        }
        return group.appending(path: "it.bloop.airmail2/Airmail", directoryHint: .isDirectory)
    }

    static func vermailRoot(override: URL?) -> URL {
        if let override {
            return override
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let sandboxed = home.appending(
            path: "Library/Containers/com.etherlord.vermail/Data/Library/Application Support/Vermail",
            directoryHint: .isDirectory
        )
        let sandboxDB = sandboxed.appending(path: "storage.sqlite")
        if FileManager.default.fileExists(atPath: sandboxDB.fileSystemPath) {
            return sandboxed
        }
        return home.appending(path: "Library/Application Support/Vermail", directoryHint: .isDirectory)
    }

    static func email(fromAccountDirectory url: URL) -> String {
        var name = url.lastPathComponent
        if let range = name.range(of: #"_\d+$"#, options: .regularExpression) {
            name.removeSubrange(range)
        }
        return name
    }

    static func sameEmail(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive]) == .orderedSame
    }
}
