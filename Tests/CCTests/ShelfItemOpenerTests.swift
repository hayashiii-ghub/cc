import CCCore
import Foundation
import Testing
@testable import CC

@MainActor
struct ShelfItemOpenerTests {
    @Test func routesRelatedFileKindsAndWebLinksToTheirSettings() async throws {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.preferences.setDestination(.application(fixture.editor), for: .textAndCode)
        fixture.preferences.setDestination(.application(fixture.viewer), for: .imagesAndPDFs)
        fixture.preferences.setDestination(.application(fixture.browser), for: .webLinks)
        let items = [
            fixture.item("draft.MD"), fixture.item("main.swift"),
            fixture.item("photo.png"), fixture.item("report.pdf"),
            fixture.link("https://example.com"), fixture.link("http://example.com"),
            fixture.item("archive.zip"), fixture.link("mailto:test@example.com")
        ]
        for item in items { try await fixture.opener.open(item) }
        #expect(fixture.calls.map(\.application) == [
            fixture.editor.url, fixture.editor.url, fixture.viewer.url, fixture.viewer.url,
            fixture.browser.url, fixture.browser.url, nil, nil
        ])
        #expect(fixture.calls.map(\.item) == items.compactMap(\.url))
    }

    @Test func settingsChangesApplyImmediatelyWithoutOpeningOrResavingAnything() async throws {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        let item = fixture.item("draft.md")
        let shelf = ShelfStoreTestFixture()
        let store = ShelfStore(repository: shelf.repository, itemOpener: fixture.opener, errorPresenter: { _ in })
        #expect(store.openingPreferences === fixture.preferences)
        store.openingPreferences.setDestination(.application(fixture.editor), for: .textAndCode)
        #expect(fixture.calls.isEmpty)
        try await fixture.opener.open(item)
        #expect(fixture.calls.last?.application == fixture.editor.url)
        store.openingPreferences.setDestination(.systemDefault, for: .textAndCode)
        try await fixture.opener.open(item)
        #expect(fixture.calls.last?.application == nil)
        #expect(fixture.preferences.mappings.isEmpty)
    }

    @Test func unavailableSavedApplicationFallsBackWithoutDeletingTheChoice() async throws {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        let item = fixture.item("draft.md")
        fixture.preferences.setDestination(.application(fixture.editor), for: .textAndCode)
        let opener = ShelfItemOpener(
            preferences: fixture.preferences,
            resolveApplication: { _ in nil },
            openURL: { url, application in fixture.calls.append((url, application)) }
        )
        try await opener.open(item)
        #expect(fixture.calls.count == 1)
        #expect(fixture.calls.first?.application == nil)
        #expect(fixture.preferences.destination(for: .textAndCode) == .application(fixture.editor))
    }

    @Test func failedSavedApplicationFallsBackAndReportsFinalFailure() async throws {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        let item = fixture.item("draft.md")
        fixture.preferences.setDestination(.application(fixture.editor), for: .textAndCode)
        var failDefault = false
        let opener = ShelfItemOpener(
            preferences: fixture.preferences,
            resolveApplication: { $0.url },
            openURL: { url, application in
                fixture.calls.append((url, application))
                if application != nil || failDefault { throw OpeningError.failed }
            }
        )
        try await opener.open(item)
        #expect(fixture.calls.map(\.application) == [fixture.editor.url, nil])
        failDefault = true
        await #expect(throws: OpeningError.failed) { try await opener.open(item) }
        #expect(fixture.preferences.destination(for: .textAndCode) == .application(fixture.editor))
    }

    @Test func finderRevealsFilesAndOpensFoldersInsteadOfLaunchingTheirDefaultApps() async throws {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.preferences.setDestination(.finder, for: .textAndCode)
        fixture.preferences.setDestination(.finder, for: .imagesAndPDFs)
        fixture.preferences.setDestination(.finder, for: .folders)
        let file = fixture.item("draft.md")
        let image = fixture.item("photo.png")
        let folder = ShelfItem(kind: .folder, title: "Sources", detail: "", url: URL(fileURLWithPath: "/tmp/Sources"))
        try await fixture.opener.open(file)
        try await fixture.opener.open(image)
        try await fixture.opener.open(folder)
        #expect(fixture.calls.isEmpty)
        #expect(fixture.finderCalls.map(\.item) == [file.url, image.url, folder.url].compactMap { $0 })
        #expect(fixture.finderCalls.map(\.isFolder) == [false, false, true])
    }

    @Test func finderFailureDoesNotUnexpectedlyOpenTheFileInAnotherApp() async throws {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.preferences.setDestination(.finder, for: .folders)
        let folder = ShelfItem(kind: .folder, title: "Sources", detail: "", url: URL(fileURLWithPath: "/tmp/Sources"))
        let opener = ShelfItemOpener(
            preferences: fixture.preferences,
            openURL: { url, application in fixture.calls.append((url, application)) },
            showInFinder: { _, _ in throw OpeningError.failed }
        )
        await #expect(throws: OpeningError.failed) { try await opener.open(folder) }
        #expect(fixture.calls.isEmpty)
    }

    @Test func shelfOpensItsStoredCopyAndReportsMissingCopies() async throws {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        let shelf = ShelfStoreTestFixture()
        try FileManager.default.createDirectory(at: shelf.rootURL, withIntermediateDirectories: true)
        let source = shelf.rootURL.appendingPathComponent("original.md")
        try Data("Original".utf8).write(to: source)
        let record = try shelf.repository.addFile(source)
        let saved = try #require(try shelf.repository.contentURL(for: record))
        var errors: [Error] = []
        let store = ShelfStore(repository: shelf.repository, itemOpener: fixture.opener, errorPresenter: { errors.append($0) })
        let item = try #require(store.items.first)
        store.openingPreferences.setDestination(.application(fixture.editor), for: .textAndCode)
        await store.open(item)?.value
        #expect(fixture.calls.first?.item == saved)
        #expect(saved != source)
        store.openingPreferences.reset(for: .textAndCode)
        await store.open(item)?.value
        #expect(fixture.calls.last?.application == nil)
        try FileManager.default.removeItem(at: saved)
        #expect(store.open(item) == nil)
        #expect(errors.count == 1)
        #expect(fixture.calls.count == 2)
    }

    @Test func pastedTextIsNeverSentToAnApplication() async throws {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.preferences.setDestination(.application(fixture.editor), for: .textAndCode)
        let text = ShelfItem(kind: .text, title: "Note", detail: "", text: "Full contents")
        try await fixture.opener.open(text)
        #expect(fixture.calls.isEmpty)
        #expect(fixture.finderCalls.isEmpty)
    }

    private enum OpeningError: Error { case failed }

    @MainActor
    private final class Fixture {
        let suiteName = "CCOpenTests-\(UUID().uuidString)"
        let defaults: UserDefaults
        let preferences: ShelfOpenPreferences
        let editor = ShelfOpenApplication(url: URL(fileURLWithPath: "/Applications/Editor.app"), bundleIdentifier: "test.editor")
        let viewer = ShelfOpenApplication(url: URL(fileURLWithPath: "/Applications/Viewer.app"), bundleIdentifier: "test.viewer")
        let browser = ShelfOpenApplication(url: URL(fileURLWithPath: "/Applications/Browser.app"), bundleIdentifier: "test.browser")
        var calls: [(item: URL, application: URL?)] = []
        var finderCalls: [(item: URL, isFolder: Bool)] = []
        lazy var opener = ShelfItemOpener(
            preferences: preferences,
            resolveApplication: { $0.url },
            openURL: { [unowned self] url, application in calls.append((url, application)) },
            showInFinder: { [unowned self] url, isFolder in finderCalls.append((url, isFolder)) }
        )

        init() {
            defaults = UserDefaults(suiteName: suiteName)!
            preferences = ShelfOpenPreferences(defaults: defaults)
        }

        func item(_ name: String) -> ShelfItem {
            ShelfItem(kind: .file, title: name, detail: "", url: URL(fileURLWithPath: "/tmp/\(name)"))
        }

        func link(_ value: String) -> ShelfItem {
            ShelfItem(kind: .link, title: value, detail: "", url: URL(string: value))
        }

        func cleanup() { defaults.removePersistentDomain(forName: suiteName) }
    }
}
