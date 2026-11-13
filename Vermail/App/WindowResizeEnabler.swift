import AppKit
import SwiftUI

/// SwiftUI sheets and the Settings scene omit the resizable window style.
struct WindowResizeEnabler: NSViewRepresentable {
    var minSize: CGSize
    var usesSystemWindowBackground = false

    func makeNSView(context _: Context) -> NSView {
        let view = ResizeSupportView()
        view.minSize = minSize
        view.usesSystemWindowBackground = usesSystemWindowBackground
        return view
    }

    func updateNSView(_ view: NSView, context _: Context) {
        guard let view = view as? ResizeSupportView else { return }
        view.minSize = minSize
        view.usesSystemWindowBackground = usesSystemWindowBackground
        view.apply()
    }
}

private final class ResizeSupportView: NSView {
    var minSize: CGSize = .zero
    var usesSystemWindowBackground = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }

    override func layout() {
        super.layout()
        apply()
    }

    func apply() {
        guard let window else { return }
        window.styleMask.insert(.resizable)
        if usesSystemWindowBackground {
            window.backgroundColor = .windowBackgroundColor
        }
        if window.minSize.width < minSize.width || window.minSize.height < minSize.height {
            window.minSize = minSize
        }
    }
}
