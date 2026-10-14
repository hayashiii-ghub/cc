import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private static let contentWidth: CGFloat = 520
    private static let preferredContentHeight: CGFloat = 640

    private let preferences: ShelfPresentationPreferences
    private let shortcutController: ShortcutController
    private let onCheckForUpdates: () -> Void
    private let onOpenReleasePage: () -> Void
    private var window: NSWindow?
    private var hostingController: NSHostingController<SettingsView>?

    init(
        preferences: ShelfPresentationPreferences,
        shortcutController: ShortcutController,
        onCheckForUpdates: @escaping () -> Void,
        onOpenReleasePage: @escaping () -> Void
    ) {
        self.preferences = preferences
        self.shortcutController = shortcutController
        self.onCheckForUpdates = onCheckForUpdates
        self.onOpenReleasePage = onOpenReleasePage
    }

    func show() {
        let window = settingsWindow()
        hostingController?.rootView = settingsView
        fitWindowToScreen(window)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private var settingsView: SettingsView {
        SettingsView(
            preferences: preferences,
            shortcutPreferences: shortcutController.preferences,
            shortcutController: shortcutController,
            onCheckForUpdates: onCheckForUpdates,
            onOpenReleasePage: onOpenReleasePage
        )
    }

    private func settingsWindow() -> NSWindow {
        if let window {
            return window
        }

        let window = SettingsWindow(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(
                    width: Self.contentWidth,
                    height: Self.preferredContentHeight
                )
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "cc: Settings"
        window.identifier = NSUserInterfaceItemIdentifier("ContextSettingsWindow")
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: Self.contentWidth, height: 400)
        window.contentMaxSize = NSSize(width: Self.contentWidth, height: 720)

        let hostingController = NSHostingController(rootView: settingsView)
        window.contentViewController = hostingController
        window.setContentSize(
            NSSize(width: Self.contentWidth, height: Self.preferredContentHeight)
        )
        window.center()

        self.hostingController = hostingController
        self.window = window
        return window
    }

    private func fitWindowToScreen(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let availableFrame = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        var frame = window.frame
        frame.size.height = min(frame.height, availableFrame.height)
        frame.origin.x = min(
            max(frame.minX, availableFrame.minX),
            availableFrame.maxX - frame.width
        )
        frame.origin.y = min(
            max(frame.minY, availableFrame.minY),
            availableFrame.maxY - frame.height
        )
        window.setFrame(frame, display: true)
    }
}

private final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers == [.command], event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
