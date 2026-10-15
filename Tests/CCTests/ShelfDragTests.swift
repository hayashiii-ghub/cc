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

    @Test func dragAllWritesEveryItemKindInShelfOrderWithNativeTypesAndUUIDs() throws {
        let items = mixedDragItems()
        let pasteboard = privatePasteboard()
        defer { pasteboard.releaseGlobally() }

        let writtenItems = try writeDragItems(items, to: pasteboard)

        #expect(writtenItems.map { $0.string(forType: ShelfDragPayload.pasteboardType) }
            == items.map { Optional($0.id.uuidString) })
        for (item, written) in zip(items, writtenItems) {
            switch item.kind {
            case .file, .folder, .image:
                #expect(written.types.contains(.fileURL))
                #expect(written.string(forType: .fileURL) == item.url?.absoluteString)
            case .link:
                #expect(written.types.contains(.URL))
                #expect(written.types.contains(.string))
                #expect(!written.types.contains(.fileURL))
                #expect(written.string(forType: .URL) == item.url?.absoluteString)
                #expect(written.string(forType: .string) == item.url?.absoluteString)
            case .text:
                #expect(written.types.contains(.string))
                #expect(!written.types.contains(.fileURL))
                #expect(written.string(forType: .string) == item.text)
            }
        }
    }

    @Test func singleTextAndSingleLinkEachProduceOneCompleteDragItem() throws {
        let items = mixedDragItems().filter { $0.kind == .text || $0.kind == .link }
        for item in items {
            let pasteboard = privatePasteboard()
            defer { pasteboard.releaseGlobally() }

            let writtenItems = try writeDragItems([item], to: pasteboard)
            let written = try #require(writtenItems.first)

            #expect(writtenItems.count == 1)
            #expect(written.string(forType: ShelfDragPayload.pasteboardType) == item.id.uuidString)
            #expect(written.string(forType: .string) == (item.kind == .text ? item.text : item.url?.absoluteString))
            #expect(!written.types.contains(.fileURL))
            if item.kind == .link {
                #expect(written.string(forType: .URL) == item.url?.absoluteString)
            }
        }
    }

    @Test func dragAllPasteboardMarkersRejectInternalDropsAndDirectImports() throws {
        let store = shelfFixture.makeStore()
        #expect(store.addClipboardText("Keep this item"))
        let before = store.items
        let pasteboard = privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        let writtenItems = try writeDragItems(mixedDragItems(), to: pasteboard)
        let providers = try writtenItems.map { item in
            let provider = NSItemProvider()
            for type in item.types {
                let data = try #require(item.data(forType: type))
                provider.registerDataRepresentation(
                    forTypeIdentifier: type.rawValue,
                    visibility: .all
                ) { completion in
                    completion(data, nil)
                    return nil
                }
            }
            return provider
        }
        #expect(providers.allSatisfy {
            $0.hasItemConformingToTypeIdentifier(ShelfDragPayload.typeIdentifier)
        })

        #expect(!store.handleDrop(providers: providers))
        store.importItems(from: providers)

        #expect(!store.isImporting)
        #expect(store.items == before)
    }

    private func mixedDragItems() -> [ShelfItem] {
        [
            ShelfItem(kind: .file, title: "notes.md", detail: "", url: URL(fileURLWithPath: "/tmp/notes.md")),
            ShelfItem(kind: .link, title: "Example", detail: "", url: URL(string: "https://example.com/review?first=1&second=two#section")),
            ShelfItem(kind: .folder, title: "Archive", detail: "", url: URL(fileURLWithPath: "/tmp/Archive", isDirectory: true)),
            ShelfItem(kind: .text, title: "Short title", detail: "", text: "Complete note\nリンク先へ 🧭\twith tabs"),
            ShelfItem(kind: .image, title: "image.png", detail: "", url: URL(fileURLWithPath: "/tmp/image.png"))
        ]
    }

    private func privatePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("cc.ShelfDragTests.\(UUID().uuidString)"))
    }

    private func writeDragItems(_ items: [ShelfItem], to pasteboard: NSPasteboard) throws -> [NSPasteboardItem] {
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects(items.map { ShelfItemDragWriter(item: $0) }))
        let writtenItems = try #require(pasteboard.pasteboardItems)
        #expect(writtenItems.count == items.count)
        return writtenItems
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
