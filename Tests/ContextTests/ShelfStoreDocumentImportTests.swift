import AppKit
import Testing
import UniformTypeIdentifiers
@testable import Context

@MainActor
struct ShelfStoreDocumentImportTests {
    private let shelfFixture = ShelfStoreTestFixture()

    @Test func importsMarkdownDataAsFile() async throws {
        try await assertDocumentImport(
            typeIdentifier: "net.daringfireball.markdown",
            suggestedName: "notes.md",
            contents: "# Notes",
            expectedExtension: "md"
        )
    }

    @Test func importsHTMLDataAsFile() async throws {
        try await assertDocumentImport(
            typeIdentifier: "public.html",
            suggestedName: "page.html",
            contents: "<h1>Page</h1>",
            expectedExtension: "html"
        )
    }

    @Test func importsUTF8PlainTextFileAsFile() async throws {
        try await assertDocumentImport(
            typeIdentifier: "public.utf8-plain-text",
            suggestedName: "notes.txt",
            contents: "Plain notes",
            expectedExtension: "txt"
        )
    }

    @Test(arguments: [
        ("public.comma-separated-values-text", "table.csv", "name,value\nA,1"),
        (UTType.pdf.identifier, "report.pdf", "%PDF-1.7"),
        (UTType.json.identifier, "settings.json", "{\"enabled\":true}"),
        ("com.example.context-binary", "archive.customext", "binary-data"),
        (UTType.data.identifier, "Makefile", "build:\n\techo ok")
    ])
    func importsArbitraryFileDataPreservingItsName(
        typeIdentifier: String,
        suggestedName: String,
        contents: String
    ) async throws {
        let item = try await importDocument(
            typeIdentifier: typeIdentifier,
            suggestedName: suggestedName,
            contents: contents
        )
        let url = try #require(item.url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(item.kind == .file)
        #expect(item.title == suggestedName)
        #expect(url.lastPathComponent == suggestedName)
        #expect(try String(contentsOf: url, encoding: .utf8) == contents)
    }

    @Test func dropRegistrationAcceptsGenericFiles() {
        #expect(ShelfStore.acceptedTypeIdentifiers.contains(UTType.item.identifier))
        #expect(ShelfStore.acceptedTypeIdentifiers.contains(UTType.data.identifier))
    }

    @Test func importsUnnamedGenericDataWithATypeBasedFallbackName() async throws {
        let store = shelfFixture.makeStore()
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.pdf.identifier,
            visibility: .all
        ) { completion in
            completion(Data("%PDF-1.7".utf8), nil)
            return nil
        }

        store.importItems(from: [provider])
        let item = try await waitForImportedItem(in: store)
        let url = try #require(item.url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(item.kind == .file)
        #expect(url.pathExtension == "pdf")
    }

    @Test func importsAFileBackedRepresentationWithAnArbitraryExtension() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContextTests-\(UUID().uuidString)", isDirectory: true)
        let sourceURL = root.appendingPathComponent("source.customext")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("file-backed".utf8).write(to: sourceURL)

        let store = shelfFixture.makeStore()
        let provider = NSItemProvider()
        provider.suggestedName = "original.customext"
        provider.registerFileRepresentation(
            forTypeIdentifier: "com.example.context-file",
            fileOptions: [],
            visibility: .all
        ) { completion in
            completion(sourceURL, true, nil)
            return nil
        }

        store.importItems(from: [provider])
        let item = try await waitForImportedItem(in: store)
        let importedURL = try #require(item.url)
        defer { try? FileManager.default.removeItem(at: importedURL) }

        #expect(item.kind == .file)
        #expect(importedURL.lastPathComponent == "original.customext")
        #expect(try String(contentsOf: importedURL, encoding: .utf8) == "file-backed")
    }

    @Test func fallsBackToTheNextAvailableFileRepresentation() async throws {
        let store = shelfFixture.makeStore()
        let provider = NSItemProvider()
        let fileName = "fallback-table-\(UUID().uuidString).csv"
        provider.suggestedName = fileName
        provider.registerFileRepresentation(
            forTypeIdentifier: "com.example.unavailable-csv",
            fileOptions: [],
            visibility: .all
        ) { completion in
            completion(nil, false, ImportTimeout())
            return nil
        }
        provider.registerDataRepresentation(
            forTypeIdentifier: "public.comma-separated-values-text",
            visibility: .all
        ) { completion in
            completion(Data("name,value\nA,1".utf8), nil)
            return nil
        }

        store.importItems(from: [provider])
        let item = try await waitForImportedItem(in: store)
        let url = try #require(item.url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(url.lastPathComponent == fileName)
        #expect(try String(contentsOf: url, encoding: .utf8) == "name,value\nA,1")
    }

    @Test func importsAFileBackedFolderRepresentation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContextTests-\(UUID().uuidString)", isDirectory: true)
        let sourceURL = root.appendingPathComponent("Source Folder", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try Data("nested".utf8).write(to: sourceURL.appendingPathComponent("nested.txt"))

        let store = shelfFixture.makeStore()
        let provider = NSItemProvider()
        provider.suggestedName = "Original Folder"
        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.folder.identifier,
            fileOptions: [.openInPlace],
            visibility: .all
        ) { completion in
            completion(sourceURL, true, nil)
            return nil
        }

        store.importItems(from: [provider])
        let item = try await waitForImportedItem(in: store)
        let importedURL = try #require(item.url)
        defer { try? FileManager.default.removeItem(at: importedURL) }

        #expect(item.kind == .folder)
        #expect(importedURL.lastPathComponent == "Original Folder")
        #expect(FileManager.default.fileExists(
            atPath: importedURL.appendingPathComponent("nested.txt").path
        ))
    }

    @Test func reportsFailedDropWithoutAddingAnEmptyItem() async throws {
        var errors: [Error] = []
        let store = shelfFixture.makeStore(errorPresenter: { errors.append($0) })
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.pdf.identifier, fileOptions: [], visibility: .all) { completion in
            completion(nil, false, ImportTimeout())
            return nil
        }
        store.importItems(from: [provider])
        for _ in 0..<100 where errors.isEmpty {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(errors.count == 1)
        #expect(!store.isImporting)
        #expect(store.items.isEmpty)
    }

    private func assertDocumentImport(
        typeIdentifier: String,
        suggestedName: String,
        contents: String,
        expectedExtension: String
    ) async throws {
        let item = try await importDocument(
            typeIdentifier: typeIdentifier,
            suggestedName: suggestedName,
            contents: contents
        )

        #expect(item.kind == .file)
        #expect(item.url?.pathExtension == expectedExtension)
        #expect(item.title == suggestedName)

        let url = try #require(item.url)
        defer {
            try? FileManager.default.removeItem(at: url)
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == contents)
    }

    private func importDocument(
        typeIdentifier: String,
        suggestedName: String,
        contents: String
    ) async throws -> ShelfItem {
        let store = shelfFixture.makeStore()
        let provider = NSItemProvider()
        provider.suggestedName = suggestedName
        provider.registerDataRepresentation(
            forTypeIdentifier: typeIdentifier,
            visibility: .all
        ) { completion in
            completion(Data(contents.utf8), nil)
            return nil
        }

        store.importItems(from: [provider])
        return try await waitForImportedItem(in: store)
    }

    private func waitForImportedItem(in store: ShelfStore) async throws -> ShelfItem {
        for _ in 0..<100 {
            if !store.isImporting, let item = store.items.first {
                return item
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        throw ImportTimeout()
    }
}

private struct ImportTimeout: Error {}
