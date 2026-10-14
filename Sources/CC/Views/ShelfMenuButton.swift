import AppKit
import SwiftUI

struct ShelfMenuButton: NSViewRepresentable {
    let onShowMenu: (NSView) -> Void
    var tint: NSColor = .labelColor
    var systemImage: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(onShowMenu: onShowMenu)
    }

    func makeNSView(context: NSViewRepresentableContext<Self>) -> NSButton {
        let button = CCMenuButton()
        button.image = menuImage
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.focusRingType = .none
        button.contentTintColor = tint
        button.target = context.coordinator
        button.action = #selector(Coordinator.showMenu(_:))
        button.toolTip = "cc: Menu"
        button.setAccessibilityLabel("cc: Menu")
        return button
    }

    func updateNSView(_ button: NSButton, context: NSViewRepresentableContext<Self>) {
        context.coordinator.onShowMenu = onShowMenu
        button.contentTintColor = tint
        button.image = menuImage
    }

    private var menuImage: NSImage? {
        guard let systemImage else { return ShelfIcon.vectorTemplateImage() }
        return NSImage(systemSymbolName: systemImage, accessibilityDescription: "cc: Menu")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .regular))
    }

    final class Coordinator: NSObject {
        var onShowMenu: (NSView) -> Void

        init(onShowMenu: @escaping (NSView) -> Void) {
            self.onShowMenu = onShowMenu
        }

        @objc func showMenu(_ sender: NSButton) {
            onShowMenu(sender)
        }
    }
}

private final class CCMenuButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
