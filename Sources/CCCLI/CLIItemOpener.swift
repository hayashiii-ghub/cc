import AppKit
import CCCore
import Foundation

@MainActor
final class CLIItemOpener {
    private static let bundleIdentifier = "work.hayashigoto.cc"
    private let applicationRootURL: URL
    private let resolveApplication: @MainActor () -> URL?
    private let requestOpen: @MainActor (URL, URL) async throws -> Void

    init(
        applicationRootURL: URL = CCRepository.applicationRootURL,
        resolveApplication: @escaping @MainActor () -> URL? = CLIItemOpener.applicationURL,
        requestOpen: @escaping @MainActor (URL, URL) async throws -> Void = CLIItemOpener.requestOpen
    ) {
        self.applicationRootURL = applicationRootURL.standardizedFileURL
        self.resolveApplication = resolveApplication
        self.requestOpen = requestOpen
    }

    func open(_ id: UUID, in repository: CCRepository) async throws {
        _ = try repository.get(id)
        // Item deep links contain only an ID, so a separate test store cannot be routed to the app.
        guard repository.rootURL == applicationRootURL else {
            throw CCRepositoryError(code: "unsupported_data_directory",
                message: "Open requires cc:'s standard data directory. Unset CC_DATA_DIR before opening an item.")
        }
        guard let application = resolveApplication() else {
            throw CCRepositoryError(code: "app_not_found", message: "The cc: app could not be found. Install cc.app before opening shelf items.")
        }
        let url = URL(string: "cc://item/\(id.uuidString)")!
        do {
            try await requestOpen(url, application)
        } catch {
            throw CCRepositoryError(code: "open_failed", message: "Could not send the open request to the cc: app. \(error.localizedDescription)")
        }
    }

    private static func applicationURL() -> URL? {
        // A second app copy exits at the single-instance guard before receiving an item URL.
        let running = NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == bundleIdentifier
        }?.bundleURL
        let bundled = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let registered = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        return [running, bundled, registered].compactMap { $0 }.first {
            $0.pathExtension.lowercased() == "app" && Bundle(url: $0)?.bundleIdentifier == bundleIdentifier
        }
    }

    private static func requestOpen(_ url: URL, application: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.promptsUserIfNeeded = true
        _ = try await NSWorkspace.shared.open([url], withApplicationAt: application, configuration: configuration)
    }
}
