import AppKit
import Foundation

@MainActor
final class ShelfItemOpener {
    typealias OpenHandler = @MainActor (URL, URL?) async throws -> Void
    typealias FinderHandler = @MainActor (URL, Bool) async throws -> Void

    let preferences: ShelfOpenPreferences
    private let resolveApplication: @MainActor (ShelfOpenApplication) -> URL?
    private let openURL: OpenHandler
    private let showInFinder: FinderHandler

    init(
        preferences: ShelfOpenPreferences? = nil,
        resolveApplication: @escaping @MainActor (ShelfOpenApplication) -> URL? = ShelfItemOpener.applicationURL,
        openURL: @escaping OpenHandler = ShelfItemOpener.openURL,
        showInFinder: @escaping FinderHandler = ShelfItemOpener.showInFinder
    ) {
        self.preferences = preferences ?? ShelfOpenPreferences()
        self.resolveApplication = resolveApplication
        self.openURL = openURL
        self.showInFinder = showInFinder
    }

    func open(_ item: ShelfItem) async throws {
        guard item.kind != .text, let url = item.url else { return }
        let destination = ShelfOpenCategory(item: item).map { preferences.destination(for: $0) }
            ?? .systemDefault
        switch destination {
        case .systemDefault:
            break
        case .finder:
            try await showInFinder(url, item.kind == .folder)
            return
        case .application(let application):
            if let applicationURL = resolveApplication(application) {
                do {
                    try await openURL(url, applicationURL)
                    return
                } catch {
                    // Keep a temporary app failure from preventing access to the item.
                }
            }
        }
        try await openURL(url, nil)
    }

    private static func showInFinder(_ url: URL, isFolder: Bool) async throws {
        if isFolder {
            guard let finderURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError,
                    userInfo: [NSLocalizedDescriptionKey: "Finder is unavailable."])
            }
            try await openURL(url, applicationURL: finderURL)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    static func applicationURL(_ application: ShelfOpenApplication) -> URL? {
        if isApplication(application.url, matching: application.bundleIdentifier) {
            return application.url
        }
        // Bundle identity lets a remembered choice survive an app being moved.
        if let identifier = application.bundleIdentifier,
           let relocated = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier),
           isApplication(relocated, matching: identifier) {
            return relocated
        }
        return nil
    }

    private static func isApplication(_ url: URL, matching identifier: String?) -> Bool {
        guard url.isFileURL,
              let values = try? url.resourceValues(forKeys: [.isApplicationKey]),
              values.isApplication == true,
              let bundle = Bundle(url: url) else { return false }
        return identifier == nil || bundle.bundleIdentifier == identifier
    }

    private static func openURL(_ url: URL, applicationURL: URL?) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.promptsUserIfNeeded = true
        if let applicationURL {
            _ = try await NSWorkspace.shared.open(
                [url], withApplicationAt: applicationURL, configuration: configuration
            )
        } else {
            _ = try await NSWorkspace.shared.open(url, configuration: configuration)
        }
    }
}
