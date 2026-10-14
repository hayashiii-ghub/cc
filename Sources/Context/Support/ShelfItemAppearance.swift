import Foundation

struct ShelfItemAppearance {
    let title: String
    let subtitle: String
    let help: String

    init(item: ShelfItem) {
        title = item.displayTitle
        let typeDescription: String
        let destination: String

        switch item.kind {
        case .file, .folder, .image:
            let type = Self.fileType(for: item)
            if item.isManagedFile {
                typeDescription = type
            } else if let url = item.url, url.isFileURL {
                let parent = url.deletingLastPathComponent().lastPathComponent
                typeDescription = "\(type) · \(parent.isEmpty || parent == "/" ? "Root" : parent)"
            } else {
                typeDescription = type
            }
            if let url = item.url, url.isFileURL {
                destination = url.path
            } else {
                destination = item.displayTitle
            }

        case .link:
            if let url = item.url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                var linkPath = components.path.isEmpty ? "/" : components.path
                if let query = components.percentEncodedQuery {
                    linkPath += "?\(query)"
                }
                if let fragment = components.fragment {
                    linkPath += "#\(fragment)"
                }
                typeDescription = "Link · \(linkPath)"
            } else {
                typeDescription = item.detail.isEmpty ? "Link" : item.detail
            }
            destination = item.url?.absoluteString ?? item.detail

        case .text:
            if let text = item.text {
                let count = text.count
                typeDescription = count == 1 ? "1 character" : "\(count) characters"
            } else {
                typeDescription = "Text"
            }
            destination = item.displayTitle
        }
        let source: String
        switch item.source {
        case "codex": source = "Codex"
        case "claude": source = "Claude Code"
        default: source = "You"
        }
        let note = item.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = note.flatMap { $0.isEmpty ? nil : $0 } ?? typeDescription
        subtitle = "\(source) · \(summary)"
        help = [subtitle, typeDescription, destination].joined(separator: "\n")
    }

    private static func fileType(for item: ShelfItem) -> String {
        if item.kind == .folder { return "Folder" }
        if let pathExtension = item.url?.pathExtension, !pathExtension.isEmpty {
            return pathExtension.uppercased()
        }
        return item.kind == .image ? "Image" : "File"
    }
}
