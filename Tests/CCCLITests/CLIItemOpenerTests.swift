import CCCore
import Foundation
import Testing
@testable import CCCLI

@MainActor
struct CLIItemOpenerTests {
    @Test func opensARegisteredFileThroughTheAppWithoutChangingEitherCopy() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let source = fixture.root.appendingPathComponent("original.md")
        try Data("Saved contents".utf8).write(to: source)
        let record = try fixture.repository.addFile(source)
        let managed = try #require(try fixture.repository.contentURL(for: record))
        try Data("Edited original".utf8).write(to: source)
        let database = fixture.data.appendingPathComponent("records.json")
        let before = try Data(contentsOf: database)
        let app = try #require(fixture.availableApplication)
        let equivalentRoot = fixture.data.appendingPathComponent("unused/..", isDirectory: true)

        try await fixture.opener(applicationRoot: equivalentRoot).open(record.id, in: fixture.repository)

        #expect(fixture.resolutionCount == 1)
        #expect(fixture.calls.count == 1)
        #expect(fixture.calls.first?.url.absoluteString == "cc://item/\(record.id.uuidString)")
        #expect(fixture.calls.first?.application == app)
        #expect(try String(contentsOf: managed, encoding: .utf8) == "Saved contents")
        #expect(try String(contentsOf: source, encoding: .utf8) == "Edited original")
        #expect(try Data(contentsOf: database) == before)
    }

    @Test func textAndLinksUseTheSameRegisteredItemRoute() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let text = try fixture.repository.addText("Stored note")
        let link = try fixture.repository.addLink(try #require(URL(string: "https://example.com/document")))
        let opener = fixture.opener()

        try await opener.open(text.id, in: fixture.repository)
        try await opener.open(link.id, in: fixture.repository)

        #expect(fixture.calls.map(\.url.absoluteString) == [
            "cc://item/\(text.id.uuidString)",
            "cc://item/\(link.id.uuidString)"
        ])
        #expect(fixture.calls.allSatisfy { $0.application == fixture.availableApplication })
        #expect(try fixture.repository.get(text.id) == text)
        #expect(try fixture.repository.get(link.id) == link)
    }

    @Test func unregisteredIDsAreRejectedBeforeResolvingOrLaunchingTheApp() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        await expectFailure("not_found") {
            try await fixture.opener().open(UUID(), in: fixture.repository)
        }

        #expect(fixture.resolutionCount == 0)
        #expect(fixture.calls.isEmpty)
    }

    @Test func missingManagedCopiesAreRejectedBeforeResolvingOrLaunchingTheApp() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let source = fixture.root.appendingPathComponent("original.txt")
        try Data("Keep original".utf8).write(to: source)
        let record = try fixture.repository.addFile(source)
        let managed = try #require(try fixture.repository.contentURL(for: record))
        try FileManager.default.removeItem(at: managed)

        await expectFailure("missing_content") {
            try await fixture.opener().open(record.id, in: fixture.repository)
        }

        #expect(fixture.resolutionCount == 0)
        #expect(fixture.calls.isEmpty)
        #expect(try String(contentsOf: source, encoding: .utf8) == "Keep original")
        #expect(try fixture.repository.list() == [record])
    }

    @Test func anotherDataDirectoryCannotLaunchAnUnrelatedAppItem() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let record = try fixture.repository.addText("Isolated store")
        let appRoot = fixture.root.appendingPathComponent("app-data", isDirectory: true)

        await expectFailure("unsupported_data_directory") {
            try await fixture.opener(applicationRoot: appRoot).open(record.id, in: fixture.repository)
        }

        #expect(fixture.resolutionCount == 0)
        #expect(fixture.calls.isEmpty)
        #expect(try fixture.repository.get(record.id) == record)
    }

    @Test func missingApplicationIsReportedWithoutRequestingAnOpen() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let record = try fixture.repository.addText("Stored note")
        fixture.availableApplication = nil

        await expectFailure("app_not_found") {
            try await fixture.opener().open(record.id, in: fixture.repository)
        }

        #expect(fixture.resolutionCount == 1)
        #expect(fixture.calls.isEmpty)
        #expect(try fixture.repository.get(record.id) == record)
    }

    @Test func failedApplicationOpenIsReportedAndKeepsTheItem() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let record = try fixture.repository.addText("Stored note")
        fixture.failsOpen = true

        await expectFailure("open_failed") {
            try await fixture.opener().open(record.id, in: fixture.repository)
        }

        #expect(fixture.resolutionCount == 1)
        #expect(fixture.calls.count == 1)
        #expect(try fixture.repository.get(record.id) == record)
    }

    private func expectFailure(_ code: String, operation: () async throws -> Void) async {
        do {
            try await operation()
            Issue.record("Expected error code \(code).")
        } catch {
            #expect((error as? CCRepositoryError)?.code == code)
        }
    }

    private enum OpeningError: Error { case failed }

    @MainActor
    private final class Fixture {
        let root: URL
        let data: URL
        var availableApplication: URL? = URL(fileURLWithPath: "/Applications/cc.app", isDirectory: true)
        var resolutionCount = 0
        var calls: [(url: URL, application: URL)] = []
        var failsOpen = false

        var repository: CCRepository { CCRepository(rootURL: data) }

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("CCCLIOpenTests-\(UUID().uuidString)", isDirectory: true)
            data = root.appendingPathComponent("data", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func opener(applicationRoot: URL? = nil) -> CLIItemOpener {
            CLIItemOpener(
                applicationRootURL: applicationRoot ?? data,
                resolveApplication: { [unowned self] in
                    resolutionCount += 1
                    return availableApplication
                },
                requestOpen: { [unowned self] url, application in
                    calls.append((url, application))
                    if failsOpen { throw OpeningError.failed }
                }
            )
        }

        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }
}
