import AppKit
import Foundation
import Testing
@testable import Context

struct FileActionServiceTests {
    @Test @MainActor func sourcePanelAcceptsMultipleFilesAndFolders() {
        let panel = FileActionService().makeSourcePanel()

        #expect(panel.canChooseFiles)
        #expect(panel.canChooseDirectories)
        #expect(panel.allowsMultipleSelection)
        #expect(panel.prompt == "Add")
    }

    @Test func exportsAllItemsUsingOriginalFileNames() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContextTests-\(UUID().uuidString)", isDirectory: true)
        let sourceDirectory = root.appendingPathComponent("Source", isDirectory: true)
        let destinationDirectory = root.appendingPathComponent("Destination", isDirectory: true)
        let markdownURL = sourceDirectory.appendingPathComponent("notes.md")
        let htmlURL = sourceDirectory.appendingPathComponent("page.html")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        try Data("# Notes".utf8).write(to: markdownURL)
        try Data("<h1>Page</h1>".utf8).write(to: htmlURL)

        let items = [
            ShelfItem(
                kind: .file,
                title: "edited-name.md",
                detail: sourceDirectory.path,
                url: markdownURL
            ),
            ShelfItem(
                kind: .file,
                title: "another-name.html",
                detail: sourceDirectory.path,
                url: htmlURL
            )
        ]

        let result = FileActionService().exportAll(items: items, to: destinationDirectory)
        #expect(result.failures.isEmpty)

        let exportedNames = try FileManager.default.contentsOfDirectory(
            at: destinationDirectory,
            includingPropertiesForKeys: nil
        ).map(\.lastPathComponent).sorted()
        #expect(exportedNames == ["notes.md", "page.html"])
        #expect(FileManager.default.fileExists(atPath: markdownURL.path))
        #expect(FileManager.default.fileExists(atPath: htmlURL.path))
    }

    @Test func reportsFailuresAndContinuesExportingRemainingItems() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContextTests-\(UUID().uuidString)", isDirectory: true)
        let destinationDirectory = root.appendingPathComponent("Destination", isDirectory: true)
        let missingURL = root.appendingPathComponent("missing.txt")
        let availableURL = root.appendingPathComponent("available.txt")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        try Data("available".utf8).write(to: availableURL)

        let items = [
            ShelfItem(kind: .file, title: "missing.txt", detail: root.path, url: missingURL),
            ShelfItem(kind: .file, title: "available.txt", detail: root.path, url: availableURL)
        ]

        let result = FileActionService().exportAll(items: items, to: destinationDirectory)

        #expect(result.exportedURLs.map(\.lastPathComponent) == ["available.txt"])
        #expect(result.failures.count == 1)
        #expect(result.failures.first?.itemTitle == "missing.txt")
    }

    @Test func exportsMixedItemsAndAvoidsNameCollisions() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContextTests-\(UUID().uuidString)", isDirectory: true)
        let firstSource = root.appendingPathComponent("First", isDirectory: true)
        let secondSource = root.appendingPathComponent("Second", isDirectory: true)
        let destinationDirectory = root.appendingPathComponent("Destination", isDirectory: true)
        let firstURL = firstSource.appendingPathComponent("notes.txt")
        let secondURL = secondSource.appendingPathComponent("notes.txt")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: firstSource, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondSource, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        try Data("first".utf8).write(to: firstURL)
        try Data("second".utf8).write(to: secondURL)

        let items = [
            ShelfItem(kind: .file, title: "notes.txt", detail: firstSource.path, url: firstURL),
            ShelfItem(kind: .file, title: "notes.txt", detail: secondSource.path, url: secondURL),
            ShelfItem(kind: .text, title: "Snippet", detail: "4 characters", text: "text")
        ]

        let result = FileActionService().exportAll(items: items, to: destinationDirectory)
        let exportedNames = result.exportedURLs.map(\.lastPathComponent).sorted()

        #expect(result.failures.isEmpty)
        #expect(exportedNames == ["Snippet.txt", "notes 2.txt", "notes.txt"])
    }

    @Test func exportsImageFilesWithoutChangingTheSource() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContextTests-\(UUID().uuidString)", isDirectory: true)
        let destinationDirectory = root.appendingPathComponent("Destination", isDirectory: true)
        let sourceURL = root.appendingPathComponent("photo.png")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        try Data("image".utf8).write(to: sourceURL)
        let item = ShelfItem(kind: .image, title: "photo.png", detail: root.path, url: sourceURL)

        let result = FileActionService().exportAll(items: [item], to: destinationDirectory)
        let exportedURL = destinationDirectory.appendingPathComponent("photo.png")

        #expect(result.failures.isEmpty)
        #expect(result.exportedURLs == [exportedURL])
        #expect(try String(contentsOf: sourceURL, encoding: .utf8) == "image")
        #expect(try String(contentsOf: exportedURL, encoding: .utf8) == "image")
    }
}

@MainActor
struct ShelfStoreExportTests {
    private let shelfFixture = ShelfStoreTestFixture()

    @Test func exportAllKeepsShelfItemsAndSourceFiles() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContextTests-\(UUID().uuidString)", isDirectory: true)
        let destinationDirectory = root.appendingPathComponent("Destination", isDirectory: true)
        let firstURL = root.appendingPathComponent("first.txt")
        let secondURL = root.appendingPathComponent("second.txt")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        try Data("first".utf8).write(to: firstURL)
        try Data("second".utf8).write(to: secondURL)

        let store = shelfFixture.makeStore()
        await store.addFileURLs([firstURL, secondURL]).value

        store.exportAllItems(to: destinationDirectory)

        #expect(store.isExporting)
        for _ in 0..<100 where store.isExporting {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(!store.isExporting)
        #expect(store.items.count == 2)
        #expect(FileManager.default.fileExists(atPath: firstURL.path))
        #expect(FileManager.default.fileExists(atPath: secondURL.path))
        #expect(FileManager.default.fileExists(
            atPath: destinationDirectory.appendingPathComponent("first.txt").path
        ))
        #expect(FileManager.default.fileExists(
            atPath: destinationDirectory.appendingPathComponent("second.txt").path
        ))
    }

    @Test func missingSourceDoesNotEnterShelfOrRemoveSuccessfulCopies() async throws {
        let source = shelfFixture.rootURL.appendingPathComponent("source.txt")
        try FileManager.default.createDirectory(at: shelfFixture.rootURL, withIntermediateDirectories: true)
        try Data("snapshot".utf8).write(to: source)
        var errors: [Error] = []
        let store = shelfFixture.makeStore(errorPresenter: { errors.append($0) })
        await store.addFileURLs([source, source.appendingPathExtension("missing")]).value
        #expect(store.items.count == 1)
        #expect(errors.count == 1)
        #expect(!store.isImporting)
        #expect(try String(contentsOf: source, encoding: .utf8) == "snapshot")
    }
}
