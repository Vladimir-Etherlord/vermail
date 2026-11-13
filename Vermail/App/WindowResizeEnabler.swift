import AppKit
import SwiftUI

/// SwiftUI sheets and the Settings scene omit the resizable window style.
struct WindowResizeEnabler: NSViewRepresentable {
    var minSize: CGSize

    func makeNSView(context _: Context) -> NSView {
        let view = ResizeSupportView()
        view.minSize = minSize
        return view
    }

    func updateNSView(_ view: NSView, context _: Context) {
        (view as? ResizeSupportView)?.minSize = minSize
        (view as? ResizeSupportView)?.apply()
    }
}

private final class ResizeSupportView: NSView {
    var minSize: CGSize = .zero

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
        if window.minSize.width < minSize.width || window.minSize.height < minSize.height {
            window.minSize = minSize
        }
    }
}
