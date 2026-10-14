import AppKit
import ContextCore
import Foundation
import UniformTypeIdentifiers

private struct FileExportSummaryError: LocalizedError {
    let result: FileExportResult
    let totalCount: Int

    var errorDescription: String? {
        "Could Not Export All Items"
    }

    var failureReason: String? {
        let failedItems = result.failures
            .prefix(3)
            .map { "\($0.itemTitle): \($0.message)" }
            .joined(separator: "\n")
        return "Exported \(result.exportedURLs.count) of \(totalCount) items. "
            + "\(result.failures.count) failed.\n\(failedItems)"
    }
}

@MainActor
final class ShelfStore: ObservableObject {
    static let acceptedTypeIdentifiers = ShelfItemImporter.acceptedTypeIdentifiers

    @Published private(set) var items: [ShelfItem] = []
    @Published private(set) var unreadItemIDs: Set<UUID> = []
    @Published private(set) var storageError: String?
    @Published private(set) var isExporting = false
    @Published private(set) var isImporting = false

    private let repository: ContextRepository
    private let fileRegistration: ShelfFileRegistration
    private var pendingImports = 0
    private var refreshTimer: Timer?
    private var seenItemIDs: Set<UUID> = []
    private let fileActions = FileActionService()
    private let inbox: ShelfInbox
    private let importer: ShelfItemImporter
    private let errorPresenter: @MainActor (Error) -> Void

    init(
        repository: ContextRepository = ContextRepository(),
        inbox: ShelfInbox? = nil,
        errorPresenter: @escaping @MainActor (Error) -> Void = ShelfStore.showAlert
    ) {
        self.repository = repository
        fileRegistration = ShelfFileRegistration(repository: repository)
        let inbox = inbox ?? ShelfInbox(directoryURL: repository.rootURL.appendingPathComponent("Imports"))
        self.inbox = inbox
        importer = ShelfItemImporter(inbox: inbox)
        self.errorPresenter = errorPresenter
        if let data = try? Data(contentsOf: seenItemsURL),
           let ids = try? JSONDecoder().decode(Set<UUID>.self, from: data) {
            seenItemIDs = ids
        }
        refresh()
    }

    func startObserving() {
        guard refreshTimer == nil else { return }
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refreshTimer?.tolerance = 0.25
    }

    func stopObserving() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refresh() {
        do {
            let records = try repository.list()
            let contentURLs = try repository.contentURLs(for: records)
            let updatedItems = records.map { record in
                ShelfItem(
                    id: record.id,
                    kind: shelfKind(record.kind),
                    title: record.title,
                    detail: record.note ?? "",
                    url: record.kind == .link ? record.text.flatMap(URL.init(string:))
                        : contentURLs[record.id],
                    text: record.text,
                    source: record.source,
                    note: record.note,
                    createdAt: record.createdAt,
                    isManagedFile: record.relativePath != nil
                )
            }
            if items != updatedItems { items = updatedItems }
            let unread = Set(items.map(\.id)).subtracting(seenItemIDs)
            if unreadItemIDs != unread { unreadItemIDs = unread }
            if storageError != nil { storageError = nil }
        } catch {
            storageError = error.localizedDescription
        }
    }

    func markSeen() {
        refresh()
        rememberSeen(Set(items.map(\.id)))
    }

    private var seenItemsURL: URL {
        repository.rootURL.appendingPathComponent("seen-items.json")
    }

    private func rememberSeen(_ ids: Set<UUID>) {
        seenItemIDs.formUnion(ids)
        seenItemIDs.formIntersection(Set(items.map(\.id)))
        unreadItemIDs.subtract(ids)
        do {
            let data = try JSONEncoder().encode(seenItemIDs)
            try data.write(to: seenItemsURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: seenItemsURL.path)
        } catch {
            storageError = error.localizedDescription
        }
    }

    private func shelfKind(_ kind: ContextItemKind) -> ShelfItemKind {
        switch kind {
        case .file: .file
        case .folder: .folder
        case .image: .image
        case .link: .link
        case .text: .text
        }
    }

    func importItems(from providers: [NSItemProvider]) {
        for provider in providers where
            !provider.hasItemConformingToTypeIdentifier(ShelfDragPayload.typeIdentifier) {
            beginImports(count: 1)
            importer.importItem(from: provider) { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    self.addImportedResult(result)
                    self.finishImport()
                }
            }
        }
    }

    @discardableResult
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.contains(where: {
            $0.hasItemConformingToTypeIdentifier(ShelfDragPayload.typeIdentifier)
        }) else {
            return false
        }

        importItems(from: providers)
        return true
    }

    @discardableResult
    func addFileURLs(_ urls: [URL]) -> Task<Void, Never> {
        enqueueFiles(urls.filter(\.isFileURL).map {
            ShelfFileImport(url: $0, isManagedFile: false)
        })
    }

    func canAddClipboardText(_ text: String?) -> Bool {
        guard let text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return !items.contains {
            $0.kind == .text && $0.text == text && $0.source == "human" && $0.note == nil
        }
    }

    @discardableResult
    func addClipboardText(_ text: String?) -> Bool {
        guard canAddClipboardText(text), let text else { return false }
        return addText(text)
    }

    func remove(_ item: ShelfItem) {
        mutate { try repository.remove(item.id) }
    }

    func clear() {
        guard !isImporting, !isExporting else { return }
        mutate { try repository.clear() }
    }

    func open(_ item: ShelfItem) {
        guard canRead(item) else { return }
        switch item.kind {
        case .file, .folder, .image:
            guard let url = item.url else { return }
            NSWorkspace.shared.open(url)
        case .link:
            guard let url = item.url else { return }
            NSWorkspace.shared.open(url)
        case .text:
            copyToPasteboard(item)
        }
    }

    func reveal(_ item: ShelfItem) {
        guard canRead(item) else { return }
        guard let url = item.url else {
            copyToPasteboard(item)
            return
        }

        switch item.kind {
        case .file, .folder, .image:
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .link:
            copyToPasteboard(item)
        case .text:
            copyToPasteboard(item)
        }
    }

    func copyToPasteboard(_ item: ShelfItem) {
        guard canRead(item) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if let url = item.url {
            pasteboard.writeObjects([url as NSURL])
        } else if let text = item.text {
            pasteboard.setString(text, forType: .string)
        }
    }

    @discardableResult
    func addItemsFromOpenPanel() -> Bool {
        guard !isImporting, !isExporting else { return false }
        let urls = fileActions.chooseSourceItems()
        guard !urls.isEmpty else { return false }
        addFileURLs(urls)
        return true
    }

    func copyItemsToChosenFolder() {
        guard !isImporting, !isExporting else { return }
        guard let destination = fileActions.chooseDestinationFolder() else { return }
        exportAllItems(to: destination)
    }

    func exportAllItems(to destination: URL) {
        guard !items.isEmpty, !isExporting, !isImporting else { return }

        let itemsToExport = items
        isExporting = true

        Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                FileActionService().exportAll(items: itemsToExport, to: destination)
            }.value

            guard let self else { return }
            isExporting = false

            if !result.failures.isEmpty {
                present(FileExportSummaryError(result: result, totalCount: itemsToExport.count))
            }
        }
    }

    private func addImportedResult(_ result: ShelfImportResult) {
        switch result {
        case let .file(url, isManaged):
            enqueueFiles([ShelfFileImport(url: url, isManagedFile: isManaged)])
        case let .link(url):
            addLink(url)
        case let .text(text):
            addText(text)
        case let .failure(error):
            present(error)
        }
    }

    @discardableResult
    private func enqueueFiles(_ files: [ShelfFileImport]) -> Task<Void, Never> {
        beginImports(count: files.count)
        return Task { @MainActor [weak self] in
            guard let self else { return }
            for file in files {
                do {
                    let record = try await self.fileRegistration.addFile(file.url)
                    self.refresh()
                    self.rememberSeen([record.id])
                    if file.isManagedFile { self.inbox.removeManagedItem(at: file.url) }
                } catch {
                    self.refresh()
                    self.present(error)
                }
                self.finishImport()
            }
        }
    }

    private func beginImports(count: Int) {
        pendingImports += count
        isImporting = pendingImports > 0
    }

    private func finishImport() {
        pendingImports = max(0, pendingImports - 1)
        isImporting = pendingImports > 0
    }

    private func addLink(_ url: URL) {
        do {
            let record = try repository.addLink(url)
            refresh()
            rememberSeen([record.id])
        } catch {
            refresh()
            present(error)
        }
    }

    @discardableResult
    private func addText(_ text: String) -> Bool {
        do {
            let record = try repository.addText(text)
            refresh()
            rememberSeen([record.id])
            return true
        } catch {
            present(error)
            return false
        }
    }

    private func mutate(_ operation: () throws -> Void) {
        do {
            try operation()
            refresh()
            rememberSeen([])
        } catch {
            refresh()
            present(error)
        }
    }

    private func canRead(_ item: ShelfItem) -> Bool {
        guard item.kind == .file || item.kind == .folder || item.kind == .image else { return true }
        guard let url = item.url, FileManager.default.fileExists(atPath: url.path) else {
            present(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError,
                userInfo: [NSLocalizedDescriptionKey: "The saved copy of \(item.title) is unavailable. Add the original file to cc: again."]))
            return false
        }
        return true
    }

    private func present(_ error: Error) {
        errorPresenter(error)
    }

    private static func showAlert(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }

}

private struct ShelfFileImport: Sendable {
    let url: URL
    let isManagedFile: Bool
}

private actor ShelfFileRegistration {
    let repository: ContextRepository

    init(repository: ContextRepository) {
        self.repository = repository
    }

    func addFile(_ url: URL) throws -> ContextRecord {
        try repository.addFile(url)
    }
}
