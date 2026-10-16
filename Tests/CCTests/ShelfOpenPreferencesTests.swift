import Foundation
import Testing
@testable import CC

@MainActor
struct ShelfOpenPreferencesTests {
    private let storageKey = "cc.openDestinations"

    @Test func exposesTheFourSettingsCategoriesInOrder() {
        #expect(ShelfOpenCategory.allCases.map(\.title) == [
            "Text & Code Files", "Images & PDFs", "Folders", "Web Links"
        ])
        #expect(ShelfOpenCategory.allCases.map(\.id) == ShelfOpenCategory.allCases.map(\.rawValue))
    }

    @Test func classifiesTextAndCodeWithoutDependingOnInstalledEditors() {
        for name in ["Review.MD", "app.ts", "view.tsx", "widget.jsx", "main.swift", "data.json",
                     "config.yaml", "script.py", "run.sh", "index.html", "theme.css", "table.csv", "page.astro"] {
            #expect(ShelfOpenCategory(item: file("/tmp/\(name)")) == .textAndCode)
        }
    }

    @Test func classifiesImagesAndPDFsBeforeTextAndKeepsFoldersSeparate() {
        for name in ["photo.PNG", "scan.jpg", "report.PDF", "diagram.svg"] {
            #expect(ShelfOpenCategory(item: file("/tmp/\(name)")) == .imagesAndPDFs)
        }
        #expect(ShelfOpenCategory(item: file("/tmp/capture.unknown", kind: .image)) == .imagesAndPDFs)
        #expect(ShelfOpenCategory(item: file("/tmp/References.md", kind: .folder)) == .folders)
    }

    @Test func includesOnlyHTTPAndHTTPSInWebLinks() {
        for value in ["https://example.com/reference", "HTTP://example.com/result"] {
            #expect(ShelfOpenCategory(item: link(value)) == .webLinks)
        }
        for value in ["mailto:hello@example.com", "obsidian://open?vault=Notes", "file:///tmp/notes.md", "relative/path"] {
            #expect(ShelfOpenCategory(item: link(value)) == nil)
        }
    }

    @Test func excludesClipboardTextAndUnknownFileTypes() throws {
        let text = ShelfItem(kind: .text, title: "Review", detail: "", text: "Full notes")
        #expect(ShelfOpenCategory(item: text) == nil)
        #expect(ShelfOpenCategory(item: file("/tmp/archive.zip")) == nil)
        #expect(ShelfOpenCategory(item: file("/tmp/binary.bin")) == nil)
        #expect(ShelfOpenCategory(item: ShelfItem(kind: .file, title: "Missing.md", detail: "")) == nil)
        #expect(ShelfOpenCategory(item: ShelfItem(
            kind: .file, title: "Remote.md", detail: "", url: URL(string: "https://example.com/a.md")
        )) == nil)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-open-category-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let unknown = directory.appendingPathComponent("unknown")
        try Data([0, 255, 0, 254, 0, 253]).write(to: unknown)
        #expect(ShelfOpenCategory(item: file(unknown.path)) == nil)
    }

    @Test func persistsAndReloadsIndependentCategoryDestinations() throws {
        try withDefaults { defaults in
            let preferences = ShelfOpenPreferences(defaults: defaults)
            let editor = application("Editor", bundleIdentifier: "example.editor")
            let browser = application("Browser", bundleIdentifier: "example.browser")
            #expect(preferences.mappings.isEmpty)
            #expect(ShelfOpenCategory.allCases.allSatisfy { preferences.destination(for: $0) == .systemDefault })
            #expect(defaults.object(forKey: storageKey) == nil)
            preferences.setDestination(.application(editor), for: .textAndCode)
            preferences.setDestination(.finder, for: .imagesAndPDFs)
            preferences.setDestination(.application(browser), for: .webLinks)
            let reloaded = ShelfOpenPreferences(defaults: defaults)
            #expect(reloaded.destination(for: .textAndCode) == .application(editor))
            #expect(reloaded.destination(for: .imagesAndPDFs) == .finder)
            #expect(reloaded.destination(for: .webLinks) == .application(browser))
            #expect(reloaded.destination(for: .folders) == .systemDefault)
            let replacement = application("Another Editor")
            preferences.setDestination(.application(replacement), for: .textAndCode)
            #expect(ShelfOpenPreferences(defaults: defaults).destination(for: .textAndCode) == .application(replacement))
        }
    }

    @Test func resetAndSystemDefaultRemoveOnlyTheSelectedOverride() throws {
        try withDefaults { defaults in
            let preferences = ShelfOpenPreferences(defaults: defaults)
            defaults.set("keep", forKey: "unrelated")
            preferences.setDestination(.application(application("Editor")), for: .textAndCode)
            preferences.setDestination(.finder, for: .imagesAndPDFs)
            preferences.reset(for: .textAndCode)
            let reloaded = ShelfOpenPreferences(defaults: defaults)
            #expect(reloaded.destination(for: .textAndCode) == .systemDefault)
            #expect(reloaded.destination(for: .imagesAndPDFs) == .finder)
            reloaded.setDestination(.systemDefault, for: .imagesAndPDFs)
            #expect(reloaded.mappings.isEmpty)
            #expect(defaults.object(forKey: storageKey) == nil)
            #expect(defaults.string(forKey: "unrelated") == "keep")
        }
    }

    @Test func normalizesFinderApplicationsAndRejectsFinderForWebLinks() throws {
        try withDefaults { defaults in
            let preferences = ShelfOpenPreferences(defaults: defaults)
            let finder = application("Finder", bundleIdentifier: "com.apple.finder")
            for category in [ShelfOpenCategory.textAndCode, .imagesAndPDFs, .folders] {
                preferences.setDestination(.application(finder), for: category)
                #expect(preferences.destination(for: category) == .finder)
            }
            let browser = ShelfOpenDestination.application(application("Browser"))
            preferences.setDestination(browser, for: .webLinks)
            preferences.setDestination(.finder, for: .webLinks)
            preferences.setDestination(.application(finder), for: .webLinks)
            #expect(preferences.destination(for: .webLinks) == browser)
            #expect(ShelfOpenPreferences(defaults: defaults).destination(for: .folders) == .finder)
            preferences.reset(for: .webLinks)
            preferences.setDestination(.application(finder), for: .webLinks)
            #expect(preferences.destination(for: .webLinks) == .systemDefault)
        }
    }

    @Test func writesOnlyTheInjectedDomainAndLeavesTheRetiredKeyUntouched() throws {
        try withDefaults { first in
            try withDefaults { second in
                let retired = Data("leave this older preference untouched".utf8)
                first.set(retired, forKey: "cc.defaultOpenApplications")
                second.set("untouched", forKey: storageKey)
                let preferences = ShelfOpenPreferences(defaults: first)
                #expect(preferences.mappings.isEmpty)
                preferences.setDestination(.finder, for: .textAndCode)
                #expect(first.data(forKey: storageKey) != nil)
                #expect(ShelfOpenPreferences(defaults: second).mappings.isEmpty)
                #expect(second.string(forKey: storageKey) == "untouched")
                preferences.reset(for: .textAndCode)
                #expect(first.data(forKey: "cc.defaultOpenApplications") == retired)
            }
        }
    }

    @Test func handlesMalformedValuesAndFiltersInvalidDestinationsWithoutRewritingOnLoad() throws {
        try withDefaults { defaults in
            let malformed: [Any] = ["not encoded preferences", Data("not JSON".utf8), Data("[]".utf8),
                Data(#"{"textAndCode":{"unsupported":{}}}"#.utf8)]
            for value in malformed {
                defaults.set(value, forKey: storageKey)
                #expect(ShelfOpenPreferences(defaults: defaults).mappings.isEmpty)
                if let data = value as? Data { #expect(defaults.data(forKey: storageKey) == data) }
                else { #expect(defaults.string(forKey: storageKey) == (value as? String)) }
            }
            let editor = ShelfOpenDestination.application(application("Editor"))
            let remote = ShelfOpenDestination.application(ShelfOpenApplication(
                url: try #require(URL(string: "https://example.com/Editor.app"))
            ))
            let finder = ShelfOpenDestination.application(application("Finder", bundleIdentifier: "com.apple.finder"))
            let saved: [String: ShelfOpenDestination] = [
                "textAndCode": editor, "imagesAndPDFs": remote,
                "folders": finder, "webLinks": .finder, "unknown": editor
            ]
            let data = try JSONEncoder().encode(saved)
            defaults.set(data, forKey: storageKey)
            let preferences = ShelfOpenPreferences(defaults: defaults)
            #expect(preferences.mappings == ["textAndCode": editor, "folders": .finder])
            #expect(defaults.data(forKey: storageKey) == data)
            preferences.setDestination(remote, for: .textAndCode)
            #expect(preferences.destination(for: .textAndCode) == editor)
            #expect(defaults.data(forKey: storageKey) == data)
        }
    }

    private func file(_ path: String, kind: ShelfItemKind = .file) -> ShelfItem {
        let url = URL(fileURLWithPath: path)
        return ShelfItem(kind: kind, title: url.lastPathComponent, detail: "", url: url)
    }

    private func link(_ value: String) -> ShelfItem {
        ShelfItem(kind: .link, title: value, detail: "", url: URL(string: value))
    }

    private func application(_ name: String, bundleIdentifier: String? = nil) -> ShelfOpenApplication {
        ShelfOpenApplication(url: URL(fileURLWithPath: "/Applications/\(name).app"), bundleIdentifier: bundleIdentifier)
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "ShelfOpenPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}
