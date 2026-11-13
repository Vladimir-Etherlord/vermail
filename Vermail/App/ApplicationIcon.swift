import AppKit

/// The Dock icon. About and the menu bar use this image so every mark stays the same.
@MainActor
enum ApplicationIcon {
    static var image: NSImage {
        NSApp.applicationIconImage
    }

    static func image(side: CGFloat) -> NSImage {
        let source = image
        guard let copy = source.copy() as? NSImage else { return source }
        copy.size = NSSize(width: side, height: side)
        copy.isTemplate = false
        return copy
    }
}
