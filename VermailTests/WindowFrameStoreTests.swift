import AppKit
import Testing
@testable import Vermail

@MainActor
struct WindowFrameStoreTests {
    @Test func savedFrameIsRestoredForTheNextWindow() {
        let name = "VermailTest-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(name)") }

        let first = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        first.setFrame(NSRect(x: 120, y: 140, width: 880, height: 640), display: false)
        first.saveFrame(usingName: name)

        let second = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        #expect(WindowFrameStore.restore(second, name: name))
        #expect(second.frame.width == 880)
        #expect(second.frame.height == 640)
    }
}
