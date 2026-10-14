import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import CC

@MainActor
struct ShelfDragTests {
    private let shelfFixture = ShelfStoreTestFixture()

    @Test func droppingShelfItemBackOntoShelfIsRejectedWithoutChangingItems() {
        let store = shelfFixture.makeStore()
        ["First", "Second", "Third"].forEach { _ = store.addClipboardText($0) }
        let ids = store.items.map(\.id)
        let first = store.items[0]

        let accepted = store.handleDrop(providers: [first.dragProvider()])

        #expect(!accepted)
        #expect(store.items.map(\.id) == ids)
        #expect(store.items.count == 3)
    }

    @Test func rowDragProviderIdentifiesAnInternalShelfDrag() {
        let fileURL = URL(fileURLWithPath: "/tmp/notes.md")
        let item = ShelfItem(kind: .file, title: "notes.md", detail: "/tmp", url: fileURL)

        let provider = item.dragProvider()

        #expect(provider.hasItemConformingToTypeIdentifier(ShelfDragPayload.typeIdentifier))
        #expect(provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))
    }

    @MainActor
    @Test func importingAnInternalRowDragDoesNotDuplicateTheShelfItem() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CCTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = root.appendingPathComponent("notes.md")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("# Notes".utf8).write(to: fileURL)

        let store = shelfFixture.makeStore()
        await store.addFileURLs([fileURL]).value
        let item = try #require(store.items.first)

        store.importItems(from: [item.dragProvider()])
        try await waitForImports(in: store)

        #expect(store.items.map(\.id) == [item.id])
    }

    @MainActor
    @Test func droppingSameFileURLWithoutInternalMarkerDoesNotDuplicate() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CCTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = root.appendingPathComponent("notes.md")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("# Notes".utf8).write(to: fileURL)

        let store = shelfFixture.makeStore()
        await store.addFileURLs([fileURL]).value
        let providerWithoutMarker = NSItemProvider(object: fileURL as NSURL)

        store.handleDrop(providers: [providerWithoutMarker])
        try await waitForImports(in: store)

        #expect(store.items.count == 1)
        #expect(store.items.first?.url != fileURL)
        #expect(store.items.first?.isManagedFile == true)
    }

    @MainActor
    @Test func optionTabAndImageDataDropCreateOneConsistentImageItem() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CCTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = root.appendingPathComponent("logo.png")
        let imageData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let store = shelfFixture.makeStore()
        defer {
            for item in store.items where item.url != fileURL {
                if let url = item.url { try? FileManager.default.removeItem(at: url) }
            }
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try imageData.write(to: fileURL)

        await store.addFileURLs([fileURL]).value

        let imageProvider = NSItemProvider()
        imageProvider.suggestedName = fileURL.lastPathComponent
        imageProvider.registerDataRepresentation(
            forTypeIdentifier: UTType.png.identifier,
            visibility: .all
        ) { completion in
            completion(imageData, nil)
            return nil
        }

        store.handleDrop(providers: [imageProvider])
        try await waitForImports(in: store)

        #expect(store.items.count == 1)
        #expect(store.items.first?.kind == .image)
        #expect(store.items.first?.title == fileURL.lastPathComponent)
        #expect(store.items.first?.url != fileURL)
        #expect(store.items.first?.isManagedFile == true)
    }

    @MainActor
    @Test func imageDataDropThenOptionTabKeepsCopiedFileWithoutDuplicating() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CCTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = root.appendingPathComponent("logo.png")
        let imageData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let store = shelfFixture.makeStore()
        defer {
            for item in store.items where item.url != fileURL {
                if let url = item.url { try? FileManager.default.removeItem(at: url) }
            }
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try imageData.write(to: fileURL)

        let imageProvider = NSItemProvider()
        imageProvider.suggestedName = fileURL.lastPathComponent
        imageProvider.registerDataRepresentation(
            forTypeIdentifier: UTType.png.identifier,
            visibility: .all
        ) { completion in
            completion(imageData, nil)
            return nil
        }

        store.handleDrop(providers: [imageProvider])
        try await waitForImports(in: store)
        await store.addFileURLs([fileURL]).value

        #expect(store.items.count == 1)
        #expect(store.items.first?.kind == .image)
        #expect(store.items.first?.title == fileURL.lastPathComponent)
        #expect(store.items.first?.url != fileURL)
        #expect(store.items.first?.isManagedFile == true)
    }

    @Test func batchDragUsesOnlyFileBackedItemsInShelfOrder() {
        let fileURL = URL(fileURLWithPath: "/tmp/notes.md")
        let folderURL = URL(fileURLWithPath: "/tmp/Archive", isDirectory: true)
        let imageURL = URL(fileURLWithPath: "/tmp/image.png")
        let items = [
            ShelfItem(kind: .file, title: "notes.md", detail: "", url: fileURL),
            ShelfItem(kind: .link, title: "Example", detail: "", url: URL(string: "https://example.com")),
            ShelfItem(kind: .folder, title: "Archive", detail: "", url: folderURL),
            ShelfItem(kind: .text, title: "Text", detail: "", text: "Text"),
            ShelfItem(kind: .image, title: "image.png", detail: "", url: imageURL)
        ]

        #expect(items.batchDragFileURLs == [fileURL, folderURL, imageURL])
    }

    @Test func batchFileWriterProvidesAFileURLAndInternalShelfMarker() {
        let fileURL = URL(fileURLWithPath: "/tmp/notes.md")
        let pasteboard = NSPasteboard(name: .drag)
        let writer = ShelfFileDragWriter(fileURL: fileURL)

        let types = writer.writableTypes(for: pasteboard)

        #expect(types.contains(.fileURL))
        #expect(types.contains(ShelfDragPayload.pasteboardType))
        #expect(writer.pasteboardPropertyList(forType: .fileURL) as? String == fileURL.absoluteString)
    }

    private func waitForImports(in store: ShelfStore) async throws {
        for _ in 0..<100 {
            if !store.isImporting { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw ShelfDragImportTimeout()
    }
}

private struct ShelfDragImportTimeout: Error {}
