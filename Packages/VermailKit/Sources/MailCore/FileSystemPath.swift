import Foundation

public extension URL {
    /// Filesystem path for `FileManager` and SQLite.
    ///
    /// `path()` percent-encodes spaces, so a check for `Application Support` looks for
    /// `Application%20Support` and misses the file that was just written.
    var fileSystemPath: String {
        path(percentEncoded: false)
    }
}
