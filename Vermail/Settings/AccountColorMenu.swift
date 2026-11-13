import AppKit
import SwiftUI

/// Popup whose swatches stay colored. SwiftUI `Picker` menus redraw symbols as templates.
struct AccountColorMenu: NSViewRepresentable {
    @Binding var selection: String

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = .systemFont(ofSize: NSFont.systemFontSize)
        button.target = context.coordinator
        button.action = #selector(Coordinator.choose(_:))
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        populate(button)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        let names = button.itemArray.compactMap { $0.representedObject as? String }
        if names != AccountAppearance.colorNames {
            populate(button)
        }
        select(button, name: selection)
    }

    private func populate(_ button: NSPopUpButton) {
        let action = button.action
        button.action = nil
        button.removeAllItems()
        for name in AccountAppearance.colorNames {
            let item = NSMenuItem(
                title: String(localized: AccountAppearance.title(forColor: name)),
                action: nil,
                keyEquivalent: ""
            )
            item.representedObject = name
            item.image = AccountAppearance.menuSwatch(named: name)
            button.menu?.addItem(item)
        }
        button.action = action
        select(button, name: selection)
    }

    private func select(_ button: NSPopUpButton, name: String) {
        guard let index = AccountAppearance.colorNames.firstIndex(of: name),
              button.indexOfSelectedItem != index else { return }
        let action = button.action
        button.action = nil
        button.selectItem(at: index)
        button.action = action
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<String>

        init(selection: Binding<String>) {
            self.selection = selection
        }

        @objc func choose(_ sender: NSPopUpButton) {
            guard let name = sender.selectedItem?.representedObject as? String else { return }
            selection.wrappedValue = name
        }
    }
}
