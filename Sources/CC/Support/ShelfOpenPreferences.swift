import Combine
import Foundation
import UniformTypeIdentifiers

enum ShelfOpenCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case textAndCode
    case imagesAndPDFs
    case folders
    case webLinks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .textAndCode: "Text & Code Files"
        case .imagesAndPDFs: "Images & PDFs"
        case .folders: "Folders"
        case .webLinks: "Web Links"
        }
    }

    init?(item: ShelfItem) {
        switch item.kind {
        case .text:
            return nil
        case .folder:
            self = .folders
        case .link:
            guard let scheme = item.url?.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else { return nil }
            self = .webLinks
        case .file, .image:
            guard let url = item.url, url.isFileURL else { return nil }
            let fileExtension = url.pathExtension.lowercased()
            let resourceType = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            let extensionType = fileExtension.isEmpty ? nil : UTType(filenameExtension: fileExtension)
            let types = [resourceType, extensionType].compactMap { $0 }
            if item.kind == .image || types.contains(where: { $0.conforms(to: .image) || $0.conforms(to: .pdf) }) {
                self = .imagesAndPDFs
            } else if types.contains(where: { $0.conforms(to: .text) || $0.conforms(to: .sourceCode) })
                || Self.textAndCodeExtensions.contains(fileExtension) {
                self = .textAndCode
            } else {
                return nil
            }
        }
    }

    private static let textAndCodeExtensions: Set<String> = [
        "txt", "text", "md", "markdown", "mdown", "mdx", "rst", "adoc", "log", "csv", "tsv",
        "c", "h", "cpp", "cc", "cxx", "hpp", "hh", "hxx", "m", "mm", "swift",
        "js", "mjs", "cjs", "jsx", "ts", "mts", "cts", "tsx", "json", "jsonc", "json5",
        "yaml", "yml", "toml", "ini", "conf", "config", "env", "properties", "plist",
        "py", "pyi", "ipynb", "rb", "php", "go", "rs", "java", "kt", "kts", "scala",
        "sh", "bash", "zsh", "fish", "ps1", "bat", "cmd", "html", "htm", "xhtml",
        "css", "scss", "sass", "less", "xml", "xsl", "sql", "vue", "svelte", "astro",
        "graphql", "gql", "tex"
    ]
}

struct ShelfOpenApplication: Codable, Equatable, Sendable {
    let url: URL
    let bundleIdentifier: String?

    init(url: URL, bundleIdentifier: String? = nil) {
        self.url = url
        self.bundleIdentifier = bundleIdentifier
    }
}

enum ShelfOpenDestination: Codable, Equatable, Sendable {
    case systemDefault
    case finder
    case application(ShelfOpenApplication)
}

@MainActor
final class ShelfOpenPreferences: ObservableObject {
    private static let storageKey = "cc.openDestinations"
    private let defaults: UserDefaults

    @Published private(set) var mappings: [String: ShelfOpenDestination]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var loaded: [String: ShelfOpenDestination] = [:]
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([String: ShelfOpenDestination].self, from: data) {
            for (key, destination) in saved {
                guard let category = ShelfOpenCategory(rawValue: key),
                      let value = Self.normalized(destination, for: category),
                      value != .systemDefault else { continue }
                loaded[key] = value
            }
        }
        mappings = loaded
    }

    func destination(for category: ShelfOpenCategory) -> ShelfOpenDestination {
        mappings[category.rawValue] ?? .systemDefault
    }

    func setDestination(_ destination: ShelfOpenDestination, for category: ShelfOpenCategory) {
        guard let value = Self.normalized(destination, for: category) else { return }
        var updated = mappings
        if value == .systemDefault {
            updated.removeValue(forKey: category.rawValue)
        } else {
            updated[category.rawValue] = value
        }
        save(updated)
    }

    func reset(for category: ShelfOpenCategory) {
        setDestination(.systemDefault, for: category)
    }

    private func save(_ updated: [String: ShelfOpenDestination]) {
        guard updated != mappings else { return }
        if updated.isEmpty {
            defaults.removeObject(forKey: Self.storageKey)
        } else {
            guard let data = try? JSONEncoder().encode(updated) else { return }
            defaults.set(data, forKey: Self.storageKey)
        }
        mappings = updated
    }

    private static func normalized(
        _ destination: ShelfOpenDestination, for category: ShelfOpenCategory
    ) -> ShelfOpenDestination? {
        switch destination {
        case .systemDefault:
            return .systemDefault
        case .finder:
            return category == .webLinks ? nil : .finder
        case .application(let application):
            guard application.url.isFileURL,
                  application.url.pathExtension.lowercased() == "app" else { return nil }
            if application.bundleIdentifier == "com.apple.finder" {
                return category == .webLinks ? nil : .finder
            }
            return destination
        }
    }
}
