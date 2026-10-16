import AppKit
import UniformTypeIdentifiers

@MainActor
final class ShelfApplicationPicker {
    func chooseApplication(
        for category: ShelfOpenCategory,
        currentApplication: ShelfOpenApplication?
    ) -> ShelfOpenApplication? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.treatsFilePackagesAsDirectories = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = true
        panel.title = "Choose Application"
        panel.prompt = "Choose"
        panel.message = "Choose an app for \(category.title.lowercased())."
        if let currentApplication {
            panel.message += "\nCurrent in cc: \(ShelfOpeningApplications.displayName(for: currentApplication))."
        }
        panel.directoryURL = currentApplication.flatMap {
            Self.application(at: $0.url)?.url.deletingLastPathComponent()
        } ?? URL(fileURLWithPath: "/Applications", isDirectory: true)

        // Keep the picker above either the settings window or floating shelf.
        panel.level = .popUpMenu
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return Self.application(at: url)
    }

    static func application(at selectedURL: URL) -> ShelfOpenApplication? {
        guard selectedURL.isFileURL else { return nil }
        let url = selectedURL.standardizedFileURL.resolvingSymlinksInPath()
        guard url.pathExtension.lowercased() == "app",
              let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey]),
              values.isDirectory == true,
              values.contentType?.conforms(to: .applicationBundle) == true,
              let bundle = Bundle(url: url) else {
            return nil
        }

        return ShelfOpenApplication(url: url, bundleIdentifier: bundle.bundleIdentifier)
    }
}
