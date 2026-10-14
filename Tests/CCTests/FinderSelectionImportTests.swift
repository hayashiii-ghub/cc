import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import CC

@MainActor
struct FinderSelectionImportTests {
    private let shelfFixture = ShelfStoreTestFixture()

    @Test func addsSelectedFilesAndFoldersToShelf() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CCTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = root.appendingPathComponent("notes.md", isDirectory: false)
        let folderURL = root.appendingPathComponent("Archive", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try Data("notes".utf8).write(to: fileURL)

        let store = shelfFixture.makeStore()
        await store.addFileURLs([fileURL, folderURL]).value

        #expect(store.items.map(\.title) == ["notes.md", "Archive"])
        #expect(store.items.map(\.kind) == [.file, .folder])
        #expect(store.items.allSatisfy { $0.isManagedFile })
        #expect(store.items.map { $0.url?.lastPathComponent } == ["notes.md", "Archive"])
    }

    @Test func addsFilesWithoutFilteringByExtension() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CCTests-\(UUID().uuidString)", isDirectory: true)
        let fileNames = [
            "table.csv",
            "vector.svg",
            "page.html",
            "notes.txt",
            "report.pdf",
            "settings.json",
            "archive.customext",
            "Makefile",
            ".env"
        ]
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURLs = try fileNames.map { fileName in
            let url = root.appendingPathComponent(fileName)
            try Data(fileName.utf8).write(to: url)
            return url
        }

        let store = shelfFixture.makeStore()
        await store.addFileURLs(fileURLs).value

        #expect(store.items.map(\.title) == fileNames)
        #expect(store.items.allSatisfy { $0.isManagedFile })
        #expect(store.items.map { $0.url?.lastPathComponent } == fileNames)
        #expect(store.items.count == fileNames.count)
    }

    @Test func convertsAppleEventListItemsWithoutJoiningPaths() {
        let descriptor = NSAppleEventDescriptor.list()
        descriptor.insert(NSAppleEventDescriptor(string: "/tmp/first item.md"), at: 1)
        descriptor.insert(NSAppleEventDescriptor(string: "/tmp/line\nbreak.html"), at: 2)

        let urls = FinderSelectionReader.fileURLs(from: descriptor)

        #expect(urls.map(\.path) == ["/tmp/first item.md", "/tmp/line\nbreak.html"])
    }

    @Test func enablesGlobalShortcutOnlyWhileFinderIsFrontmost() {
        #expect(FinderShortcutAvailability.isEnabled(
            frontmostBundleIdentifier: FinderSelectionReader.finderBundleIdentifier
        ))
        #expect(!FinderShortcutAvailability.isEnabled(
            frontmostBundleIdentifier: "com.apple.TextEdit"
        ))
        #expect(!FinderShortcutAvailability.isEnabled(frontmostBundleIdentifier: nil))
    }

    @Test func definesSeparateAddAndToggleShelfShortcuts() {
        let addSelection = ShelfShortcut.addFinderSelection
        let toggleShelf = ShelfShortcut.toggleShelf

        #expect(addSelection.keyCode == UInt32(kVK_Tab))
        #expect(addSelection.modifiers == UInt32(optionKey))
        #expect(toggleShelf.keyCode == UInt32(kVK_Tab))
        #expect(toggleShelf.modifiers == UInt32(optionKey | shiftKey))
        #expect(addSelection.identifier.id != toggleShelf.identifier.id)
        #expect(addSelection.matches(addSelection.identifier))
        #expect(!addSelection.matches(toggleShelf.identifier))
        #expect(toggleShelf.matches(toggleShelf.identifier))
        #expect(!toggleShelf.matches(addSelection.identifier))
    }
}
