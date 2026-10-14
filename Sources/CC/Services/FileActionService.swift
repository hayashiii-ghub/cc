import AppKit
import Foundation

struct FileExportFailure: Sendable {
    let itemTitle: String
    let message: String
}

struct FileExportResult: Sendable {
    let exportedURLs: [URL]
    let failures: [FileExportFailure]
}

struct FileActionService {
    func chooseSourceItems() -> [URL] {
        let panel = makeSourcePanel()
        return panel.runModal() == .OK ? panel.urls : []
    }

    func makeSourcePanel() -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        return panel
    }

    func chooseDestinationFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        return panel.runModal() == .OK ? panel.url : nil
    }

    func exportAll(items: [ShelfItem], to destination: URL) -> FileExportResult {
        var exportedURLs: [URL] = []
        var failures: [FileExportFailure] = []

        for item in items {
            do {
                let url = try export(item: item, to: destination)
                exportedURLs.append(url)
            } catch {
                failures.append(
                    FileExportFailure(
                        itemTitle: item.displayTitle,
                        message: error.localizedDescription
                    )
                )
            }
        }

        return FileExportResult(
            exportedURLs: exportedURLs,
            failures: failures
        )
    }

    private func export(item: ShelfItem, to destination: URL) throws -> URL {
        switch item.kind {
        case .file, .folder, .image:
            guard let source = item.url else {
                throw CocoaError(.fileNoSuchFile)
            }
            let target = destination.availableChildURL(named: item.preferredFileName(fallback: source.lastPathComponent))
            try FileManager.default.copyItem(at: source, to: target)
            return target
        case .link:
            let name = item.title.sanitizedFileName(defaultName: "Link") + ".url.txt"
            let target = destination.availableChildURL(named: name)
            try (item.url?.absoluteString ?? item.text ?? "").write(to: target, atomically: true, encoding: .utf8)
            return target
        case .text:
            let name = item.title.sanitizedFileName(defaultName: "Text") + ".txt"
            let target = destination.availableChildURL(named: name)
            try (item.text ?? "").write(to: target, atomically: true, encoding: .utf8)
            return target
        }
    }
}
