import AppKit
import CCCore
import Testing
import UniformTypeIdentifiers
@testable import CC

@MainActor
struct ShelfStoreLifecycleTests {
    @Test func removingAnImportedFileDeletesItsManagedCopy() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let store = ShelfStore(repository: CCRepository(rootURL: fixture.rootURL.appendingPathComponent("Shelf")), inbox: ShelfInbox(directoryURL: fixture.inboxURL))

        store.importItems(from: [provider(name: "notes.txt", contents: "notes")])
        let item = try await waitForImportedItem(in: store)
        let managedURL = try #require(item.url)

        #expect(item.isManagedFile)
        #expect(FileManager.default.fileExists(atPath: managedURL.path))

        store.remove(item)

        #expect(store.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: managedURL.path))
    }

    @Test func removingAnExternalFileNeverDeletesTheSource() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let sourceURL = fixture.rootURL.appendingPathComponent("source.txt")
        try Data("source".utf8).write(to: sourceURL)
        let store = ShelfStore(repository: CCRepository(rootURL: fixture.rootURL.appendingPathComponent("Shelf")), inbox: ShelfInbox(directoryURL: fixture.inboxURL))

        await store.addFileURLs([sourceURL]).value
        let item = try #require(store.items.first)
        #expect(item.isManagedFile)
        #expect(item.url != sourceURL)

        store.remove(item)

        #expect(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    @Test func clearDeletesManagedCopiesAndPreservesExternalSources() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let sourceURL = fixture.rootURL.appendingPathComponent("source.txt")
        try Data("source".utf8).write(to: sourceURL)
        let store = ShelfStore(repository: CCRepository(rootURL: fixture.rootURL.appendingPathComponent("Shelf")), inbox: ShelfInbox(directoryURL: fixture.inboxURL))

        await store.addFileURLs([sourceURL]).value
        store.importItems(from: [provider(name: "managed.txt", contents: "managed")])
        let managedItem = try await waitForItem(named: "managed.txt", in: store)
        let managedURL = try #require(managedItem.url)

        store.clear()

        #expect(store.items.isEmpty)
        #expect(FileManager.default.fileExists(atPath: sourceURL.path))
        #expect(!FileManager.default.fileExists(atPath: managedURL.path))
    }

    @Test func addingTheOriginalFileKeepsAnEquivalentManagedCopy() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let sourceURL = fixture.rootURL.appendingPathComponent("table.csv")
        try Data("name,value\nA,1".utf8).write(to: sourceURL)
        let store = ShelfStore(repository: CCRepository(rootURL: fixture.rootURL.appendingPathComponent("Shelf")), inbox: ShelfInbox(directoryURL: fixture.inboxURL))

        store.importItems(from: [
            provider(
                name: "table.csv",
                contents: "name,value\nA,1",
                typeIdentifier: "public.comma-separated-values-text"
            )
        ])
        let managedItem = try await waitForImportedItem(in: store)
        let managedURL = try #require(managedItem.url)

        await store.addFileURLs([sourceURL]).value

        #expect(store.items.count == 1)
        #expect(store.items.first?.url == managedURL)
        #expect(store.items.first?.isManagedFile == true)
        #expect(FileManager.default.fileExists(atPath: managedURL.path))
    }

    @Test func relaunchPreservesSnapshotsAfterTheSourceDisappears() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let repository = CCRepository(rootURL: fixture.rootURL.appendingPathComponent("Shelf"))
        let sourceURL = fixture.rootURL.appendingPathComponent("source.txt")
        try Data("original snapshot".utf8).write(to: sourceURL)
        let firstStore = ShelfStore(repository: repository)
        await firstStore.addFileURLs([sourceURL]).value
        let firstID = try #require(firstStore.items.first?.id)
        try FileManager.default.removeItem(at: sourceURL)

        let reopened = ShelfStore(repository: repository)
        let copyURL = try #require(reopened.items.first?.url)
        #expect(reopened.items.first?.id == firstID)
        #expect(try String(contentsOf: copyURL, encoding: .utf8) == "original snapshot")
        #expect(reopened.unreadItemIDs.isEmpty)
    }

    @Test func externalAdditionsRefreshWithoutLosingUnseenItems() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let repository = CCRepository(rootURL: fixture.rootURL.appendingPathComponent("Shelf"))
        let store = ShelfStore(repository: repository)
        let external = try repository.addText(String(repeating: "Long document\n", count: 10_000), source: "codex", note: "Full draft")
        store.refresh()
        #expect(store.items.first?.text == external.text)
        #expect(store.items.first?.source == "codex")
        #expect(store.items.first?.note == "Full draft")
        #expect(store.unreadItemIDs == [external.id])

        store.addClipboardText("Human note")
        #expect(store.items.count == 2)
        #expect(store.unreadItemIDs == [external.id])
        store.markSeen()
        #expect(store.unreadItemIDs.isEmpty)
        #expect(ShelfStore(repository: repository).unreadItemIDs.isEmpty)
    }

    @Test func queuedImportsBlockBulkActionsAndPreserveConcurrentAgentAdditions() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let repository = CCRepository(rootURL: fixture.rootURL.appendingPathComponent("Shelf"))
        let existing = try repository.addText("Existing note")
        let source = fixture.rootURL.appendingPathComponent("source.txt")
        let destination = fixture.rootURL.appendingPathComponent("Export", isDirectory: true)
        try Data("saved copy".utf8).write(to: source)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let store = ShelfStore(repository: repository)
        store.markSeen()

        let importing = store.addFileURLs([source])
        #expect(store.isImporting)
        store.clear()
        store.exportAllItems(to: destination)
        #expect(!store.isExporting)
        #expect(store.items.map(\.id) == [existing.id])

        let agent = try repository.addText("Agent draft", source: "codex", note: "Ready for review")
        store.refresh()
        await importing.value

        #expect(!store.isImporting)
        #expect(store.items.count == 3)
        #expect(store.items.contains { $0.id == existing.id })
        #expect(store.items.contains { $0.id == agent.id })
        #expect(store.unreadItemIDs == [agent.id])
        #expect(try repository.list().count == 3)
        #expect(try String(contentsOf: source, encoding: .utf8) == "saved copy")
        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
    }

    @Test func failedRegistrationRetainsTheImportedStagingFile() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let repository = CCRepository(rootURL: fixture.rootURL.appendingPathComponent("Shelf"))
        _ = try repository.list()
        try Data("invalid records".utf8).write(to: repository.rootURL.appendingPathComponent("records.json"))
        var errors: [Error] = []
        let store = ShelfStore(repository: repository, inbox: ShelfInbox(directoryURL: fixture.inboxURL),
            errorPresenter: { errors.append($0) })

        store.importItems(from: [provider(name: "retained.txt", contents: "retain on failure")])
        for _ in 0..<100 where store.isImporting {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(!store.isImporting)
        #expect(errors.count == 1)
        #expect(store.items.isEmpty)
        #expect(store.storageError != nil)
        #expect(try String(contentsOf: fixture.inboxURL.appendingPathComponent("retained.txt"), encoding: .utf8) == "retain on failure")
    }

    @Test func corruptStorageIsReportedAndCannotBeReplacedByAnAdd() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let shelfRoot = fixture.rootURL.appendingPathComponent("Shelf")
        let repository = CCRepository(rootURL: shelfRoot)
        _ = try repository.list()
        let recordsURL = shelfRoot.appendingPathComponent("records.json")
        let corrupt = Data("not a shelf".utf8)
        try corrupt.write(to: recordsURL)
        var errors: [Error] = []
        let store = ShelfStore(repository: repository, errorPresenter: { errors.append($0) })
        #expect(store.storageError != nil)
        #expect(!store.addClipboardText("should not overwrite"))
        #expect(errors.count == 1)
        #expect(try Data(contentsOf: recordsURL) == corrupt)
    }

    private func provider(
        name: String,
        contents: String,
        typeIdentifier: String = UTType.utf8PlainText.identifier
    ) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = name
        provider.registerDataRepresentation(
            forTypeIdentifier: typeIdentifier,
            visibility: .all
        ) { completion in
            completion(Data(contents.utf8), nil)
            return nil
        }
        return provider
    }

    private func waitForImportedItem(in store: ShelfStore) async throws -> ShelfItem {
        for _ in 0..<100 {
            if !store.isImporting, let item = store.items.first(where: \.isManagedFile) {
                return item
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw LifecycleTimeout()
    }

    private func waitForItem(named name: String, in store: ShelfStore) async throws -> ShelfItem {
        for _ in 0..<100 {
            if !store.isImporting, let item = store.items.first(where: { $0.title == name }) {
                return item
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw LifecycleTimeout()
    }
}

private struct Fixture {
    let rootURL: URL
    let inboxURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CCTests-\(UUID().uuidString)", isDirectory: true)
        inboxURL = rootURL.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private struct LifecycleTimeout: Error {}
