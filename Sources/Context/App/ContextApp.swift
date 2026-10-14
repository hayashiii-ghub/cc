import AppKit
import Combine
import CoreFoundation
import OSLog
import Sparkle

private let finderImportLogger = Logger(
    subsystem: "work.hayashigoto.Context",
    category: "FinderImport"
)

#if DEBUG
private let contextDemoNotificationCallback: CFNotificationCallback = {
    _, observer, name, _, _ in
    guard let observer, let name else { return }

    let application = Unmanaged<ContextApplication>
        .fromOpaque(observer)
        .takeUnretainedValue()
    let notificationName = name.rawValue as String
    Task { @MainActor in
        application.handleDemoNotification(named: notificationName)
    }
}
#endif

@main
@MainActor
final class ContextApplication: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let bundleIdentifier = "work.hayashigoto.Context"
    private static let shared = ContextApplication()
    private static var singleInstanceGuard: SingleInstanceGuard?
    private static let releasesURL = URL(
        string: "https://github.com/hayashiii-ghub/context/releases/latest"
    )!

    private let store = ShelfStore()
    private let presentationPreferences = ShelfPresentationPreferences()
    private let shortcutPreferences = ShortcutPreferences()
    private lazy var shortcutController = ShortcutController(
        preferences: shortcutPreferences,
        onAddFinderSelection: { [weak self] in self?.addFinderSelection() },
        onToggleShelf: { [weak self] in self?.toggleShelf() }
    )
    private let finderSelectionReader = FinderSelectionReader()
    private let updateController = AppUpdateController()
    private lazy var settingsWindowController = SettingsWindowController(
        preferences: presentationPreferences,
        shortcutController: shortcutController,
        onCheckForUpdates: { [weak self] in
            self?.updateController.controller.checkForUpdates(nil)
        },
        onOpenReleasePage: { [weak self] in
            self?.openReleasePage()
        }
    )
    private lazy var menuBarShelfController = MenuBarShelfController(
        store: store,
        onShowMenu: { [weak self] view in
            self?.showShelfMenu(relativeTo: view)
        }
    )
    private lazy var notchShelfController: NotchIslandController = NotchIslandController(
        store: store,
        onAddFinderSelection: { [weak self] in
            self?.notchShelfController.hideShelf()
            self?.addFiles()
        },
        onShowMenu: { [weak self] view in
            self?.showShelfMenu(relativeTo: view)
        },
        onWillShow: { [weak self] in
            self?.menuBarShelfController.hideShelf()
        }
    )
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var unreadItemsObserver: AnyCancellable?
    private var presentationObserver: AnyCancellable?
    private var copyMenuItem: NSMenuItem?
    private var addClipboardMenuItem: NSMenuItem?
    private var clearMenuItem: NSMenuItem?
    private var menuTrackingDepth = 0

#if DEBUG
    private static let demoNotificationPrefix = "work.hayashigoto.Context.demo."
#endif

    static func main() {
        guard let instanceGuard = SingleInstanceGuard(identifier: bundleIdentifier) else {
            activateRunningInstance()
            return
        }
        singleInstanceGuard = instanceGuard

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = shared
        terminateDuplicateInstances()
        app.run()
    }

    private static func activateRunningInstance() {
        let runningInstance = NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == bundleIdentifier
        }
        runningInstance?.activate(options: [])
    }

    private static func terminateDuplicateInstances() {
        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        for application in NSWorkspace.shared.runningApplications where
            application.processIdentifier != currentProcessIdentifier
            && application.bundleIdentifier == bundleIdentifier {
            application.terminate()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.startObserving()

        configureStatusItem()
        observeUnreadItems()
        configureApplicationMenu()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuTrackingDidBegin),
            name: NSMenu.didBeginTrackingNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuTrackingDidEnd),
            name: NSMenu.didEndTrackingNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        updateController.start()
        updatePresentationAvailability()
        presentationObserver = presentationPreferences.$mode
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in
                self?.applyPresentationMode(mode)
            }
        shortcutController.start(finderIsFrontmost: FinderShortcutAvailability.isEnabled(
            frontmostBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        ))
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostApplicationDidChange),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        updateFinderSelectionHotKey(
            frontmostBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        )
#if DEBUG
        configureDemoTriggers()
#endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
#if DEBUG
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque()
        )
#endif
        menuBarShelfController.hideShelf()
        notchShelfController.stop()
        shortcutController.stop()
        unreadItemsObserver = nil
        presentationObserver = nil
        store.stopObserving()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let link = ContextDeepLink(url: url) else { continue }
            store.refresh()
            switch link {
            case .shelf: showShelf()
            case .clipboard: addClipboardText()
            case .settings: showSettings()
            case .item(let id):
                if let item = store.items.first(where: { $0.id == id }) {
                    store.open(item)
                } else {
                    showShelf()
                }
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        let hasItems = !store.items.isEmpty
        let canManageItems = hasItems && !store.isExporting && !store.isImporting
        copyMenuItem?.isEnabled = canManageItems
        clearMenuItem?.isEnabled = canManageItems
        menu.items.first { $0.action == #selector(addFiles) }?.isEnabled = !store.isExporting && !store.isImporting
        let clipboard = NSPasteboard.general.string(forType: .string)
        addClipboardMenuItem?.isEnabled = !store.isExporting && store.canAddClipboardText(clipboard)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = ShelfIcon.templateImage()
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(statusItemButtonPressed(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let menu = NSMenu(title: "cc:")
        menu.delegate = self
        menu.autoenablesItems = false
        menu.addItem(NSMenuItem(title: "Add Files…", action: #selector(addFiles), keyEquivalent: "o"))
        let clipboardItem = NSMenuItem(title: "Add Clipboard Text", action: #selector(addClipboardText), keyEquivalent: "")
        addClipboardMenuItem = clipboardItem
        menu.addItem(clipboardItem)
        menu.addItem(.separator())

        let copyItem = NSMenuItem(title: "Copy All to Folder…", action: #selector(copyItems), keyEquivalent: "")
        copyMenuItem = copyItem
        menu.addItem(copyItem)
        let clearItem = NSMenuItem(title: "Clear Shelf", action: #selector(clearShelf), keyEquivalent: "")
        clearItem.toolTip = "Remove items from cc:. Original files stay where they are."
        clearMenuItem = clearItem
        menu.addItem(clearItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit cc:", action: #selector(quit), keyEquivalent: "q"))
        for entry in menu.items where entry.action != nil {
            entry.target = self
        }
        statusMenu = menu
        statusItem = item
    }

    private func configureApplicationMenu() {
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "cc:")
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        applicationMenu.addItem(settingsItem)
        applicationMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit cc:", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        applicationMenu.addItem(quitItem)
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.delegate = self
        fileMenu.autoenablesItems = false
        let addFilesItem = NSMenuItem(title: "Add Files…", action: #selector(addFiles), keyEquivalent: "o")
        addFilesItem.target = self
        fileMenu.addItem(addFilesItem)
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        NSApp.mainMenu = mainMenu
    }

    private func observeUnreadItems() {
        unreadItemsObserver = store.$unreadItemIDs
            .removeDuplicates()
            .sink { [weak self] ids in
                guard let button = self?.statusItem?.button else { return }
                button.image = ShelfIcon.templateImage(hasUnreadItems: !ids.isEmpty)
                let label = ids.isEmpty ? "cc:" : "cc: · \(ids.count) new \(ids.count == 1 ? "item" : "items")"
                button.toolTip = label
                button.setAccessibilityLabel(label)
            }
    }

    @objc private func statusItemButtonPressed(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
        } else {
            let event = NSApp.currentEvent
            let eventWindow = event?.window
            let eventLocation = event.flatMap { event in
                eventWindow?.convertPoint(toScreen: event.locationInWindow)
            }
            toggleShelf(
                relativeTo: sender,
                clickLocation: eventLocation ?? NSEvent.mouseLocation,
                clickScreen: eventWindow?.screen
            )
        }
    }

    @objc private func addFiles() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.store.isImporting, self.store.addItemsFromOpenPanel() else { return }
            self.showShelf()
        }
    }

    @objc private func addClipboardText() {
        guard store.addClipboardText(NSPasteboard.general.string(forType: .string)) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.showShelf()
        }
    }

    @objc private func frontmostApplicationDidChange(_ notification: Notification) {
        let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication
        updateFinderSelectionHotKey(frontmostBundleIdentifier: application?.bundleIdentifier)
    }

    private func updateFinderSelectionHotKey(frontmostBundleIdentifier: String?) {
        shortcutController.updateFinderAvailability(FinderShortcutAvailability.isEnabled(
            frontmostBundleIdentifier: frontmostBundleIdentifier
        ))
    }

    @objc private func addFinderSelection() {
        let frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard frontmostBundleIdentifier == FinderSelectionReader.finderBundleIdentifier else {
            finderImportLogger.info(
                "Ignored shortcut for frontmost app: \(frontmostBundleIdentifier ?? "unknown", privacy: .public)"
            )
            return
        }

        guard importCurrentFinderSelection() else { return }
        showShelf()
    }

    @discardableResult
    private func importCurrentFinderSelection() -> Bool {
        do {
            let urls = try finderSelectionReader.selectedFileURLs()
            guard !urls.isEmpty else {
                finderImportLogger.info("Finder selection was empty")
                return false
            }
            store.addFileURLs(urls)
            finderImportLogger.info("Added \(urls.count) Finder selection item(s)")
            return true
        } catch {
            finderImportLogger.error("Finder selection failed: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert(error: error)
            alert.messageText = "Could Not Read Finder Selection"
            alert.runModal()
            return false
        }
    }

#if DEBUG
    private func configureDemoTriggers() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        for command in Self.demoCommands {
            CFNotificationCenterAddObserver(
                center,
                observer,
                contextDemoNotificationCallback,
                Self.demoNotificationName(command),
                nil,
                .deliverImmediately
            )
        }
    }

    private static let demoCommands = [
        "add-finder-selection",
        "clear-shelf",
        "show-shelf",
        "toggle-shelf",
        "use-menu-bar",
        "use-notch-island",
        "show-settings",
    ]

    private static func demoNotificationName(_ command: String) -> CFString {
        ((demoNotificationPrefix + command) as NSString) as CFString
    }

    fileprivate func handleDemoNotification(named name: String) {
        switch name {
        case Self.demoNotificationPrefix + "add-finder-selection":
            guard importCurrentFinderSelection() else { return }
            showShelf()
        case Self.demoNotificationPrefix + "clear-shelf":
            store.clear()
        case Self.demoNotificationPrefix + "show-shelf":
            showShelf()
        case Self.demoNotificationPrefix + "toggle-shelf":
            toggleShelf()
        case Self.demoNotificationPrefix + "use-menu-bar":
            presentationPreferences.mode = .menuBar
        case Self.demoNotificationPrefix + "use-notch-island":
            presentationPreferences.mode = .notch
        case Self.demoNotificationPrefix + "show-settings":
            showSettings()
        default:
            break
        }
    }
#endif

    @objc private func copyItems() {
        DispatchQueue.main.async { [weak self] in
            self?.store.copyItemsToChosenFolder()
        }
    }

    @objc private func clearShelf() {
        store.clear()
    }

    @objc private func openReleasePage() {
        NSWorkspace.shared.open(Self.releasesURL)
    }

    @objc private func showSettings() {
        DispatchQueue.main.async { [weak self] in
            self?.menuBarShelfController.hideShelf()
            self?.notchShelfController.hideShelf()
            self?.settingsWindowController.show()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showShelf() {
        let location = NSEvent.mouseLocation
        guard let (screen, mode) = presentationTarget(location: location) else { return }
        if mode == .notch {
            notchShelfController.showShelf(on: screen)
            return
        }
        guard let button = statusItem?.button else { return }
        notchShelfController.hideShelf()
        menuBarShelfController.showShelf(
            relativeTo: button,
            clickLocation: location,
            clickScreen: screen
        )
    }

    private func toggleShelf(
        relativeTo clickedButton: NSStatusBarButton? = nil,
        clickLocation: NSPoint? = nil,
        clickScreen: NSScreen? = nil
    ) {
        let location = clickLocation ?? NSEvent.mouseLocation
        guard let (screen, mode) = presentationTarget(
            location: location,
            preferredScreen: clickScreen
        ) else { return }
        if mode == .notch {
            notchShelfController.toggleShelf(on: screen)
            return
        }
        guard let button = clickedButton ?? statusItem?.button else { return }
        notchShelfController.hideShelf()
        menuBarShelfController.toggleShelf(
            relativeTo: button,
            clickLocation: location,
            clickScreen: screen
        )
    }

    private func presentationTarget(
        location: NSPoint,
        preferredScreen: NSScreen? = nil
    ) -> (NSScreen, ShelfPresentationMode)? {
        let screens = NSScreen.screens
        let descriptors = screens.compactMap { screen -> ShelfScreenDescriptor? in
            guard let id = screen.contextShelfDisplayID else { return nil }
            return ShelfScreenDescriptor(
                id: id,
                frame: screen.frame,
                hasNotch: screen.contextNotchGeometry != nil
            )
        }
        guard let route = ShelfScreenPolicy.route(
            screens: descriptors,
            location: location,
            preferredScreenID: preferredScreen?.contextShelfDisplayID,
            mode: presentationPreferences.mode
        ), let screen = screens.first(where: { $0.contextShelfDisplayID == route.screenID }) else {
            return nil
        }
        return (screen, route.mode)
    }

    @objc private func screenParametersDidChange() {
        updatePresentationAvailability()
        menuBarShelfController.handleScreenChanges()
        synchronizeNotch()
    }

    private func updatePresentationAvailability() {
        presentationPreferences.hasNotchedDisplay = NSScreen.screens.contains {
            $0.contextNotchGeometry != nil
        }
    }

    private func applyPresentationMode(_ mode: ShelfPresentationMode) {
        menuBarShelfController.hideShelf()
        notchShelfController.stop()
        if mode == .notch {
            synchronizeNotch()
        }
    }

    private func synchronizeNotch() {
        guard presentationPreferences.mode == .notch,
              let screen = NSScreen.screens.first(where: { $0.contextNotchGeometry != nil }) else {
            notchShelfController.stop()
            return
        }
        _ = notchShelfController.start(on: screen)
    }

    private func showStatusMenu() {
        guard let statusItem, let statusMenu else { return }

        menuBarShelfController.hideShelf()
        notchShelfController.hideShelf()
        statusItem.menu = statusMenu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func showShelfMenu(relativeTo view: NSView) {
        guard let statusMenu else { return }
        let y = view.isFlipped ? view.bounds.maxY + 4 : view.bounds.minY - 4
        statusMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: view)
    }

    @objc private func menuTrackingDidBegin() {
        menuTrackingDepth += 1
        guard menuTrackingDepth == 1 else { return }
        // Item menus also extend outside the shelf and must not trigger dismissal.
        menuBarShelfController.beginMenuTracking()
        notchShelfController.beginMenuTracking()
    }

    @objc private func menuTrackingDidEnd() {
        menuTrackingDepth = max(0, menuTrackingDepth - 1)
        guard menuTrackingDepth == 0 else { return }
        menuBarShelfController.endMenuTracking()
        notchShelfController.endMenuTracking()
    }

}
