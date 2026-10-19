import AppKit
import Combine
import CoreGraphics
import OSLog
import SwiftUI

private let notchIslandDropLogger = Logger(
    subsystem: "work.hayashigoto.cc",
    category: "NotchDrop"
)

private let notchIslandWindowLogger = Logger(
    subsystem: "work.hayashigoto.cc",
    category: "Windowing"
)

@MainActor
final class NotchIslandController: NSObject {
    private let store: ShelfStore
    private let onWillShow: () -> Void
    private let onAddFinderSelection: () -> Void
    private let onShowSettings: () -> Void
    private let onClearAll: () -> Void
    private let presentation = NotchIslandPresentationState()
    private var phaseBeforeDrop: NotchIslandPhase = .compact
    private var geometry: NotchScreenGeometry?
    private var preferredScreenID: UInt32?
    private var panel: NSPanel?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var confirmationTask: Task<Void, Never>?
    private var panelVerificationTask: Task<Void, Never>?
    private var itemCountObserver: AnyCancellable?

    init(
        store: ShelfStore,
        onAddFinderSelection: @escaping () -> Void,
        onShowSettings: @escaping () -> Void,
        onClearAll: @escaping () -> Void,
        onWillShow: @escaping () -> Void = {}
    ) {
        self.store = store
        self.onWillShow = onWillShow
        self.onAddFinderSelection = onAddFinderSelection
        self.onShowSettings = onShowSettings
        self.onClearAll = onClearAll
        super.init()
        itemCountObserver = store.$items
            .map { $0.count }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] count in
                self?.resizePanel(itemCount: count)
            }
    }

    @discardableResult
    func start(on screen: NSScreen? = nil) -> Bool {
        if let screen {
            preferredScreenID = screen.ccShelfDisplayID
        }
        guard refreshScreen() else {
            stopMouseTracking()
            return false
        }
        startMouseTracking()
        return true
    }

    func stop() {
        confirmationTask?.cancel()
        confirmationTask = nil
        phaseBeforeDrop = .compact
        presentation.phase = .compact
        geometry = nil
        preferredScreenID = nil
        stopMouseTracking()
        stopEventMonitors()
        discardPanel()
    }

    func hideShelf() {
        guard presentation.phase != .compact else { return }
        confirmationTask?.cancel()
        confirmationTask = nil
        phaseBeforeDrop = .compact
        presentation.phase = .compact
        stopEventMonitors()
        updateMouseCapture()
    }

    func beginMenuTracking() {
        stopEventMonitors()
    }

    func endMenuTracking() {
        if isShelfExpanded {
            startEventMonitors()
        }
    }

    var screenID: UInt32? {
        preferredScreenID
    }

    private func refreshScreen(allowRecovery: Bool = true) -> Bool {
        guard let preferredScreenID,
              let targetScreen = NSScreen.screens.first(where: {
                  $0.ccShelfDisplayID == preferredScreenID
              }),
              let geometry = targetScreen.ccNotchGeometry else {
            self.geometry = nil
            stopEventMonitors()
            stopMouseTracking()
            discardPanel()
            return false
        }
        if let panel, !WindowServerPresentation.isOnScreen(panel) {
            discardPanel()
        }
        let needsHostingUpdate = panel == nil || self.geometry != geometry
        self.geometry = geometry
        if needsHostingUpdate {
            configurePanel(for: geometry)
        }
        panel?.setFrame(geometry.expandedFrame(itemCount: store.items.count), display: true)
        panel?.orderFrontRegardless()
        updateMouseCapture()
        schedulePanelVerification(allowRecovery: allowRecovery)
        return true
    }

    private func configurePanel(for geometry: NotchScreenGeometry) {
        let frame = geometry.expandedFrame(itemCount: store.items.count)
        let panel = panel ?? makePanel(frame: frame)
        panel.identifier = NSUserInterfaceItemIdentifier("CCIslandPanel-\(preferredScreenID ?? 0)")
        let rootView = NotchIslandView(
            store: store,
            presentation: presentation,
            topInset: geometry.topInset,
            notchWidth: geometry.notchFrame.width,
            sideTabWidth: NotchScreenGeometry.idleSideTabWidth,
            contentWidth: frame.width,
            onToggleExpanded: { [weak self] in
                self?.toggleShelf()
            },
            onAddFinderSelection: { [weak self] in
                self?.onAddFinderSelection()
            },
            onShowSettings: { [weak self] in
                self?.onShowSettings()
            },
            onClearAll: { [weak self] in
                self?.onClearAll()
            }
        )
        panel.contentView = NotchIslandDropReceiverView(
            acceptedTypeIdentifiers: ShelfStore.acceptedTypeIdentifiers,
            presentation: presentation,
            rootView: rootView,
            onTargetChange: { [weak self] isTargeted in
                self?.setDropTargeted(isTargeted)
            },
            onDrop: { [weak self] providers in
                guard let self, self.store.handleDrop(providers: providers) else { return false }
                self.showAcceptedState()
                return true
            }
        )
    }

    private func resizePanel(itemCount: Int) {
        guard let geometry, let panel else { return }
        let frame = geometry.expandedFrame(itemCount: itemCount)
        guard frame != panel.frame else { return }
        panel.setFrame(frame, display: true)
        panel.contentView?.layoutSubtreeIfNeeded()
        updateMouseCapture()
    }

    private func makePanel(frame: NSRect) -> NSPanel {
        let panel = NotchIslandPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // The black Island also needs a dark appearance for AppKit-backed menu controls.
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = true
        self.panel = panel
        return panel
    }

    func toggleShelf(on screen: NSScreen? = nil) {
        if isShelfExpanded, screen == nil || screen?.ccShelfDisplayID == preferredScreenID {
            hideShelf()
        } else {
            showShelf(on: screen)
        }
    }

    func showShelf(on screen: NSScreen? = nil) {
        guard start(on: screen) else { return }
        onWillShow()
        store.refresh()
        store.markSeen()
        confirmationTask?.cancel()
        confirmationTask = nil
        phaseBeforeDrop = .expanded
        presentation.phase = .expanded
        startEventMonitors()
        panel?.ignoresMouseEvents = false
        panel?.orderFrontRegardless()
        panel?.makeKey()
        schedulePanelVerification(allowRecovery: true)
    }

    private func schedulePanelVerification(allowRecovery: Bool) {
        panelVerificationTask?.cancel()
        guard allowRecovery, let presentedPanel = panel else { return }

        panelVerificationTask = Task { @MainActor [weak self, weak presentedPanel] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled,
                  let self,
                  let presentedPanel,
                  self.panel === presentedPanel,
                  !WindowServerPresentation.isOnScreen(presentedPanel) else {
                return
            }

            let wasExpanded = self.isShelfExpanded
            notchIslandWindowLogger.error(
                "Notch Island panel did not reach WindowServer; recreating it"
            )
            self.discardPanel()
            guard self.refreshScreen(allowRecovery: false) else { return }
            if wasExpanded {
                self.panel?.ignoresMouseEvents = false
                self.panel?.makeKey()
            }
        }
    }

    private func discardPanel() {
        panelVerificationTask?.cancel()
        panelVerificationTask = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
    }

    private var isShelfExpanded: Bool {
        if presentation.phase == .expanded {
            return true
        }
        return (presentation.phase == .targeted || presentation.phase == .accepted)
            && phaseBeforeDrop == .expanded
    }

    private func setDropTargeted(_ isTargeted: Bool) {
        guard presentation.phase != .accepted else { return }

        if isTargeted {
            guard presentation.phase != .targeted else { return }
            phaseBeforeDrop = presentation.phase
            presentation.phase = .targeted
        } else if presentation.phase == .targeted {
            presentation.phase = phaseBeforeDrop
            updateMouseCapture()
        }
    }

    private func showAcceptedState() {
        confirmationTask?.cancel()
        phaseBeforeDrop = .compact
        presentation.showAcceptedDrop()

        confirmationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled, let self else { return }
            self.presentation.finishAcceptedDrop()
            self.stopEventMonitors()
            self.updateMouseCapture()
        }
    }

    private func startMouseTracking() {
        stopMouseTracking()

        let handler: (NSEvent) -> Void = { [weak self] event in
            DispatchQueue.main.async {
                self?.updateForMouseEvent(event)
            }
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .leftMouseUp],
            handler: handler
        )
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .leftMouseUp]
        ) { event in
            handler(event)
            return event
        }
    }

    private func stopMouseTracking() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func updateForMouseEvent(_ event: NSEvent) {
        let isDragging = event.type == .leftMouseDragged
            || CGEventSource.buttonState(.combinedSessionState, button: .left)
        guard let geometry, let panel, panel.isVisible else { return }

        if !isDragging {
            updateMouseCapture()

            if event.type == .leftMouseUp {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    guard self?.presentation.phase == .targeted else { return }
                    self?.setDropTargeted(false)
                }
            }
            return
        }

        if presentation.phase == .expanded {
            panel.ignoresMouseEvents = !geometry.expandedFrame(itemCount: store.items.count).contains(NSEvent.mouseLocation)
            return
        }

        let isNearNotch = geometry.dropFrame.contains(NSEvent.mouseLocation)
        if isNearNotch {
            panel.ignoresMouseEvents = false
            if presentation.phase == .compact {
                setDropTargeted(true)
            }
        } else if presentation.phase == .targeted {
            panel.ignoresMouseEvents = true
            setDropTargeted(false)
        }
    }

    private func updateMouseCapture() {
        guard let panel else { return }
        panel.ignoresMouseEvents = !currentVisibleFrame.contains(NSEvent.mouseLocation)
    }

    private var currentVisibleFrame: NSRect {
        guard let geometry else { return .zero }
        switch presentation.phase {
        case .compact:
            return geometry.compactFrame
        case .targeted, .accepted:
            return geometry.dropFrame
        case .expanded:
            return geometry.expandedFrame(itemCount: store.items.count)
        }
    }

    private func startEventMonitors() {
        stopEventMonitors()

        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self, NSApp.modalWindow == nil else { return event }

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
        guard isShelfExpanded, !currentVisibleFrame.contains(location) else { return }
        hideShelf()
    }
}

private final class NotchIslandDropReceiverView: NSView {
    private let acceptedTypes: [NSPasteboard.PasteboardType]
    private let presentation: NotchIslandPresentationState
    private let visibleNotchWidth: CGFloat
    private let visibleTopInset: CGFloat
    private let visibleSideTabWidth: CGFloat
    private let hostingView: NotchIslandHostingView
    private var onTargetChange: (Bool) -> Void
    private var onDrop: ([NSItemProvider]) -> Bool
    private var isTargeted = false

    init(
        acceptedTypeIdentifiers: [String],
        presentation: NotchIslandPresentationState,
        rootView: NotchIslandView,
        onTargetChange: @escaping (Bool) -> Void,
        onDrop: @escaping ([NSItemProvider]) -> Bool
    ) {
        acceptedTypes = acceptedTypeIdentifiers.map {
            NSPasteboard.PasteboardType(rawValue: $0)
        }
        self.presentation = presentation
        visibleNotchWidth = rootView.notchWidth
        visibleTopInset = rootView.topInset
        visibleSideTabWidth = rootView.sideTabWidth
        hostingView = NotchIslandHostingView(rootView: rootView)
        self.onTargetChange = onTargetChange
        self.onDrop = onDrop
        super.init(frame: .zero)
        hostingView.sizingOptions = []
        registerForDraggedTypes(acceptedTypes)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard interactionRect.contains(point) else { return nil }
        return super.hitTest(point)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard canAccept(sender.draggingPasteboard) else { return [] }
        notchIslandDropLogger.debug("Drag entered notch target")
        setTargeted(true)
        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard canAccept(sender.draggingPasteboard) else { return [] }
        setTargeted(true)
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        setTargeted(false)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer { setTargeted(false) }
        guard canAccept(sender.draggingPasteboard) else { return false }
        let providers = Self.itemProviders(from: sender.draggingPasteboard)
        guard !providers.isEmpty else {
            notchIslandDropLogger.error("Notch drop did not yield item providers")
            return false
        }
        let accepted = onDrop(providers)
        notchIslandDropLogger.debug("Performed notch drop; accepted: \(accepted)")
        return accepted
    }

    private var interactionRect: NSRect {
        let size: NSSize
        switch presentation.phase {
        case .compact:
            size = NSSize(
                width: visibleNotchWidth + visibleSideTabWidth * 2,
                height: visibleTopInset
            )
        case .targeted, .accepted:
            size = NSSize(
                width: max(
                    NotchScreenGeometry.dropMinimumWidth,
                    visibleNotchWidth + visibleSideTabWidth * 2
                ),
                height: visibleTopInset + NotchScreenGeometry.dropExtraHeight
            )
        case .expanded:
            size = bounds.size
        }

        return NSRect(
            x: bounds.midX - size.width / 2,
            y: bounds.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func setTargeted(_ targeted: Bool) {
        guard isTargeted != targeted else { return }
        isTargeted = targeted
        onTargetChange(targeted)
    }

    private func canAccept(_ pasteboard: NSPasteboard) -> Bool {
        let internalType = NSPasteboard.PasteboardType(ShelfDragPayload.typeIdentifier)
        guard pasteboard.availableType(from: [internalType]) == nil else { return false }
        return pasteboard.availableType(from: acceptedTypes) != nil
    }

    fileprivate static func itemProviders(from pasteboard: NSPasteboard) -> [NSItemProvider] {
        (pasteboard.pasteboardItems ?? []).compactMap { item in
            let provider = NSItemProvider()
            var registeredTypeCount = 0

            for type in item.types {
                guard let data = item.data(forType: type) else { continue }
                registeredTypeCount += 1
                provider.registerDataRepresentation(
                    forTypeIdentifier: type.rawValue,
                    visibility: .all
                ) { completion in
                    completion(data, nil)
                    return nil
                }

                if type == .fileURL,
                   let rawURL = String(data: data, encoding: .utf8),
                   let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    provider.suggestedName = url.lastPathComponent
                }
            }

            return registeredTypeCount > 0 ? provider : nil
        }
    }
}

private final class NotchIslandHostingView: NSHostingView<NotchIslandView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

private final class NotchIslandPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}
