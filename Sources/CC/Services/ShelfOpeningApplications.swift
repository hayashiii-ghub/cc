import AppKit
import UniformTypeIdentifiers

@MainActor
enum ShelfOpeningApplications {
    static func candidates(for category: ShelfOpenCategory) -> [ShelfOpenApplication] {
        let workspace = NSWorkspace.shared
        let urls: [URL]
        switch category {
        case .textAndCode:
            urls = workspace.urlsForApplications(toOpen: UTType.plainText)
                + workspace.urlsForApplications(toOpen: UTType.sourceCode)
        case .imagesAndPDFs:
            urls = workspace.urlsForApplications(toOpen: UTType.image)
                + workspace.urlsForApplications(toOpen: UTType.pdf)
        case .folders:
            urls = workspace.urlsForApplications(toOpen: UTType.folder)
        case .webLinks:
            urls = workspace.urlsForApplications(toOpen: URL(string: "https://example.com")!)
        }

        var seen: Set<String> = []
        let applications = urls.compactMap { url -> ShelfOpenApplication? in
            guard let application = ShelfApplicationPicker.application(at: url),
                  isSuggested(application),
                  seen.insert(application.bundleIdentifier ?? application.url.path).inserted else {
                return nil
            }
            return application
        }
        return applications.prefix(8).sorted {
            displayName(for: $0).localizedStandardCompare(displayName(for: $1)) == .orderedAscending
        }
    }

    static func displayName(for application: ShelfOpenApplication) -> String {
        let name = FileManager.default.displayName(atPath: application.url.path)
        return name.lowercased().hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    private static func isSuggested(_ application: ShelfOpenApplication) -> Bool {
        if let identifier = application.bundleIdentifier,
           identifier == "com.apple.finder" || identifier == "work.hayashigoto.cc"
            || identifier == Bundle.main.bundleIdentifier {
            return false
        }
        guard let bundle = Bundle(url: application.url) else { return false }
        return (bundle.object(forInfoDictionaryKey: "LSBackgroundOnly") as? Bool) != true
            && (bundle.object(forInfoDictionaryKey: "LSUIElement") as? Bool) != true
    }
}
