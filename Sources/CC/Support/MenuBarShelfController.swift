import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarShelfController: NSObject, NSWindowDelegate {
    private static let menuBarGap: CGFloat = 4
    private static let screenEdgeInset: CGFloat = 8

    private let store: ShelfStore
    private let onShowMenu: (NSView) -> Void
    private var panel: NSPanel?
    private var anchorFrame = NSRect.zero
    private var presentedScreenID: UInt32?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var itemCountObserver: AnyCancellable?

    init(
        store: ShelfStore,
        onShowMenu: @escaping (NSView) -> Void
    ) {
        self.store = store
        self.onShowMenu = onShowMenu
        super.init()
        itemCountObserver = store.$items
            .map { $0.count }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] count in
                self?.resizeVisiblePanel(itemCount: count)
            }
    }

    var isShelfVisible: Bool {
        panel?.isVisible == true
    }

    func showShelf(
        relativeTo button: NSStatusBarButton,
        clickLocation: NSPoint? = nil,
        clickScreen: NSScreen? = nil
    ) {
        store.refresh()
        let panel = shelfPanel()

        guard positionPanel(
            panel,
            relativeTo: button,
            clickLocation: clickLocation,
            clickScreen: clickScreen
        ) else { return }
        store.markSeen()
        startEventMonitors()
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func toggleShelf(
        relativeTo button: NSStatusBarButton,
        clickLocation: NSPoint? = nil,
        clickScreen: NSScreen? = nil
    ) {
        let targetScreen = clickScreen ?? clickLocation.flatMap { location in
            NSScreen.screens.first { $0.frame.contains(location) }
        } ?? button.window?.screen
        if isShelfVisible, targetScreen?.ccShelfDisplayID == presentedScreenID {
            hideShelf()
        } else {
            showShelf(
                relativeTo: button,
                clickLocation: clickLocation,
                clickScreen: clickScreen
            )
        }
    }

    func hideShelf() {
        panel?.orderOut(nil)
        stopEventMonitors()
    }

    func handleScreenChanges() {
        guard isShelfVisible, let panel, let presentedScreenID else { return }
        guard let screen = NSScreen.screens.first(where: {
            $0.ccShelfDisplayID == presentedScreenID
        }) else {
            hideShelf()
            return
        }

        var frame = panel.frame
        frame.origin.x = min(
            max(frame.minX, screen.frame.minX + Self.screenEdgeInset),
            screen.frame.maxX - frame.width - Self.screenEdgeInset
        )
        frame.origin.y = screen.visibleFrame.maxY - frame.height - Self.menuBarGap
        panel.setFrame(frame, display: true)
        anchorFrame.origin.y = screen.visibleFrame.maxY
    }

    func beginMenuTracking() {
        stopEventMonitors()
    }

    func endMenuTracking() {
        if isShelfVisible {
            startEventMonitors()
        }
    }

    private func shelfPanel() -> NSPanel {
        if let panel {
            return panel
        }

        let size = ShelfLayout.size(itemCount: store.items.count)
        let panel = MenuBarShelfPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.identifier = NSUserInterfaceItemIdentifier("CCMenuBarShelfPanel")
        let hostingController = NSHostingController(
            rootView: ContentView(
                store: store,
                onDismiss: { [weak self] in
                    self?.hideShelf()
                },
                onShowMenu: onShowMenu
            )
        )
        // The item-count layout owns the panel height, including its empty drop area.
        hostingController.sizingOptions = []
        hostingController.view.autoresizingMask = [.width, .height]
        hostingController.view.autoresizesSubviews = true
        hostingController.view.frame = NSRect(origin: .zero, size: size)
        if let hostingView = hostingController.view as? NSHostingView<ContentView> {
            hostingView.sizingOptions = []
        }
        panel.contentViewController = hostingController
        panel.contentView?.autoresizesSubviews = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.delegate = self

        self.panel = panel
        return panel
    }

    private func positionPanel(
        _ panel: NSPanel,
        relativeTo button: NSStatusBarButton,
        clickLocation: NSPoint?,
        clickScreen: NSScreen?
    ) -> Bool {
        guard let anchorWindow = button.window else { return false }

        // Status-item clicks use screen coordinates; opening without a click
        // uses the host window instead of the button's local coordinate space.
        let anchorCenterX = clickLocation?.x ?? anchorWindow.frame.midX
        let screen = clickScreen ?? clickLocation.flatMap { location in
            NSScreen.screens.first { $0.frame.contains(location) }
        } ?? anchorWindow.screen
        guard let screen else { return false }

        let availableFrame = screen.frame
        let size = ShelfLayout.size(itemCount: store.items.count)

        var origin = NSPoint(
            x: anchorCenterX - size.width / 2,
            y: screen.visibleFrame.maxY - size.height - Self.menuBarGap
        )
        origin.x = min(
            max(origin.x, availableFrame.minX + Self.screenEdgeInset),
            availableFrame.maxX - size.width - Self.screenEdgeInset
        )

        anchorFrame = NSRect(
            x: anchorCenterX - button.bounds.width / 2,
            y: screen.visibleFrame.maxY,
            width: button.bounds.width,
            height: max(screen.frame.maxY - screen.visibleFrame.maxY, button.bounds.height)
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        presentedScreenID = screen.ccShelfDisplayID
        return true
    }

    private func resizeVisiblePanel(itemCount: Int) {
        guard let panel, panel.isVisible else { return }
        let frame = ShelfLayout.resizedFrame(panel.frame, itemCount: itemCount)
        guard frame != panel.frame else { return }
        panel.setFrame(frame, display: true)
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.invalidateShadow()
    }

    private func startEventMonitors() {
        stopEventMonitors()

        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }

            if event.type == .keyDown, event.keyCode == 53 {
                self.hideShelf()
                return nil
            }

            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                self.hideShelfIfClickedOutside(at: NSEvent.mouseLocation)
            }
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.hideShelfIfClickedOutside(at: NSEvent.mouseLocation)
            }
        }
    }

    private func stopEventMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }

    private func hideShelfIfClickedOutside(at location: NSPoint) {
        guard let panel, panel.isVisible else { return }
        guard !panel.frame.contains(location), !anchorFrame.contains(location) else { return }
        hideShelf()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideShelf()
        return false
    }
}

private final class MenuBarShelfPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}
