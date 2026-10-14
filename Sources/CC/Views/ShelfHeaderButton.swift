import AppKit
import SwiftUI

struct ShelfHeaderButton: NSViewRepresentable {
    let systemImage: String
    let title: String
    var tint: NSColor = .labelColor
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: NSViewRepresentableContext<Self>) -> NSButton {
        let button = CCHeaderButton()
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.focusRingType = .none
        button.target = context.coordinator
        button.action = #selector(Coordinator.performAction(_:))
        updateNSView(button, context: context)
        return button
    }

    func updateNSView(_ button: NSButton, context: NSViewRepresentableContext<Self>) {
        context.coordinator.action = action
        button.contentTintColor = tint
        button.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .regular))
        button.toolTip = title
        button.setAccessibilityLabel(title)
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func performAction(_ sender: NSButton) {
            action()
        }
    }
}

private final class CCHeaderButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
