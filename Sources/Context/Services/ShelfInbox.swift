import Foundation

struct ShelfInbox {
    private let directoryOverride: URL?

    init(directoryURL: URL? = nil) {
        directoryOverride = directoryURL
    }

    func directory() throws -> URL {
        let directory: URL
        if let directoryOverride {
            directory = directoryOverride
        } else {
            let baseURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            directory = baseURL.appendingPathComponent("Context/Inbox", isDirectory: true)
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func removeManagedItem(at url: URL) {
        guard owns(url) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func copyItem(at sourceURL: URL, named requestedName: String) throws -> URL {
        let destinationURL = try directory().availableChildURL(named: requestedName)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    private func owns(_ url: URL) -> Bool {
        guard let directory = try? directory() else { return false }
        let directoryPath = directory.standardizedFileURL.path
        let itemPath = url.standardizedFileURL.path
        return itemPath.hasPrefix(directoryPath + "/")
    }
}
