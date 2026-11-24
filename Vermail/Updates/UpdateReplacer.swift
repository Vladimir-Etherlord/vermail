import Foundation

struct UpdateReplacement: Sendable {
    var application: URL
    var destination: URL
    var parentPID: Int32
    var helperPID: Int32
}

enum UpdateFinish: Equatable, Sendable {
    /// Used by tests: the caller waits until the copy is in place and nothing is reopened.
    case wait
    /// Used by the helper: the script waits until this process exits, then replaces and reopens Vermail.
    case relaunch
}

enum UpdateReplaceError: Error, LocalizedError, Sendable {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(details):
            details.isEmpty ? "The update could not be installed." : details
        }
    }
}

/// Replaces a `Vermail.app` bundle after the processes that are using it have exited.
enum UpdateReplacer {
    static func unzip(_ zip: URL, into directory: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.path(percentEncoded: false)) {
            try fileManager.removeItem(at: directory)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try run(
            "/usr/bin/ditto",
            ["-x", "-k", zip.path(percentEncoded: false), directory.path(percentEncoded: false)]
        )
    }

    static func application(in directory: URL) -> URL? {
        let fileManager = FileManager.default
        if let found = bundle(in: directory, fileManager: fileManager) {
            return found
        }
        guard let children = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return nil }
        return children.compactMap { bundle(in: $0, fileManager: fileManager) }.first
    }

    static func replace(_ replacement: UpdateReplacement, finish: UpdateFinish) throws {
        let script = try writeScript()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = arguments(script: script, replacement: replacement, finish: finish)
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        guard finish == .wait else { return }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errors.fileHandleForReading.readDataToEndOfFile()
            throw UpdateReplaceError.commandFailed(String(decoding: data, as: UTF8.self))
        }
    }

    private static func bundle(in directory: URL, fileManager: FileManager) -> URL? {
        let candidate = directory.appending(path: "Vermail.app", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: candidate.path(percentEncoded: false)) else { return nil }
        return candidate
    }

    private static func writeScript() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "vermail-update-\(UUID().uuidString).sh")
        try Data(scriptSource.utf8).write(to: url, options: .atomic)
        return url
    }

    private static func arguments(script: URL, replacement: UpdateReplacement, finish: UpdateFinish) -> [String] {
        [
            script.path(percentEncoded: false),
            String(replacement.parentPID),
            String(replacement.helperPID),
            replacement.application.path(percentEncoded: false),
            replacement.destination.path(percentEncoded: false),
            finish == .relaunch ? "open" : "quiet",
        ]
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errors.fileHandleForReading.readDataToEndOfFile()
            throw UpdateReplaceError.commandFailed(String(decoding: data, as: UTF8.self))
        }
    }

    private static let scriptSource = """
    #!/bin/sh
    parent="$1"
    helper="$2"
    source="$3"
    destination="$4"
    mode="$5"
    tries=0
    while /bin/kill -0 "$parent" 2>/dev/null || /bin/kill -0 "$helper" 2>/dev/null; do
      tries=$((tries + 1))
      if [ "$tries" -gt 900 ]; then
        /bin/kill -9 "$helper" 2>/dev/null || true
        /bin/kill -9 "$parent" 2>/dev/null || true
        break
      fi
      /bin/sleep 0.2
    done
    /bin/rm -rf "$destination"
    /usr/bin/ditto "$source" "$destination" || exit 1
    /usr/bin/xattr -dr com.apple.quarantine "$destination" || true
    if [ "$mode" = "open" ]; then
      /usr/bin/open "$destination" || exit 1
    fi
    """
}
