import CCCore
import Darwin
import Foundation
import Testing

@_silgen_name("flock")
private func testFlock(_ descriptor: Int32, _ operation: Int32) -> Int32

struct CCRepositoryTests {
    @Test func copiesFilesAndKeepsThemAcrossSourceChangesAndRestarts() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("source.txt")
        try Data("original".utf8).write(to: source)
        let repository = CCRepository(rootURL: fixture.data)
        let record = try repository.addFile(source, source: "codex", note: "A completed document")
        let managed = try #require(try repository.contentURL(for: record))
        #expect(managed.path != source.path)
        #expect(record.originalPath == source.path)
        #expect(record.source == "codex")
        try Data("edited".utf8).write(to: source)
        try FileManager.default.removeItem(at: source)
        let restarted = CCRepository(rootURL: fixture.data)
        #expect(try restarted.get(record.id) == record)
        let reloaded = try #require(try restarted.contentURL(for: record))
        #expect(try String(contentsOf: reloaded, encoding: .utf8) == "original")
    }

    @Test func removalAndClearDeleteCopiesButKeepOriginalFiles() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("original.txt")
        try Data("keep".utf8).write(to: source)
        let repository = CCRepository(rootURL: fixture.data)
        let first = try repository.addFile(source)
        let managed = try #require(try repository.contentURL(for: first))
        try repository.remove(first.id)
        #expect(!FileManager.default.fileExists(atPath: managed.path))
        #expect(try String(contentsOf: source, encoding: .utf8) == "keep")
        _ = try repository.addFile(source)
        _ = try repository.addText("A note")
        try repository.clear()
        #expect(try repository.list().isEmpty)
        #expect(try String(contentsOf: source, encoding: .utf8) == "keep")
    }

    @Test func confirmedClearRequiresTheExactRecordIDs() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("original.txt")
        try Data("keep original".utf8).write(to: source)
        let repository = CCRepository(rootURL: fixture.data)
        let file = try repository.addFile(source)
        let note = try repository.addText("Confirmed note")
        let managed = try #require(try repository.contentURL(for: file))
        let database = fixture.data.appendingPathComponent("records.json")
        let before = try Data(contentsOf: database)

        #expect(try !repository.clear(expectedIDs: [file.id, UUID()]))
        #expect(try Data(contentsOf: database) == before)
        #expect(try String(contentsOf: managed, encoding: .utf8) == "keep original")

        #expect(try repository.clear(expectedIDs: [file.id, note.id]))
        #expect(try repository.list().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: managed.path))
        #expect(try String(contentsOf: source, encoding: .utf8) == "keep original")
    }

    @Test func confirmedClearPreservesAgentCopiesAddedAfterThePrompt() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let repository = CCRepository(rootURL: fixture.data)
        let source = fixture.root.appendingPathComponent("confirmed.txt")
        let agentSource = fixture.root.appendingPathComponent("agent.txt")
        try Data("confirmed copy".utf8).write(to: source)
        try Data("new agent copy".utf8).write(to: agentSource)
        let confirmed = try repository.addFile(source)
        let expectedIDs: Set<UUID> = [confirmed.id]
        let agent = try CCRepository(rootURL: fixture.data).addFile(agentSource, source: "codex")
        let managed = try #require(try repository.contentURL(for: confirmed))
        let agentManaged = try #require(try repository.contentURL(for: agent))
        let database = fixture.data.appendingPathComponent("records.json")
        let before = try Data(contentsOf: database)

        #expect(try !repository.clear(expectedIDs: expectedIDs))
        #expect(try Set(repository.list().map(\.id)) == [confirmed.id, agent.id])
        #expect(try Data(contentsOf: database) == before)
        #expect(try String(contentsOf: managed, encoding: .utf8) == "confirmed copy")
        #expect(try String(contentsOf: agentManaged, encoding: .utf8) == "new agent copy")
        #expect(try String(contentsOf: source, encoding: .utf8) == "confirmed copy")
        #expect(try String(contentsOf: agentSource, encoding: .utf8) == "new agent copy")
    }

    @Test func cleanupFailureDoesNotRestoreAlreadyDeletedMetadata() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("original.txt")
        try Data("original".utf8).write(to: source)
        let repository = CCRepository(rootURL: fixture.data)
        let record = try repository.addFile(source)
        let managed = try #require(try repository.contentURL(for: record))
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: managed.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: managed.path) }
        do {
            try repository.remove(record.id)
            Issue.record("Immutable saved content must report cleanup failure.")
        } catch let error as CCRepositoryError {
            #expect(error.code == "cleanup_failed")
        }
        #expect(try repository.list().isEmpty)
        #expect(try String(contentsOf: source, encoding: .utf8) == "original")
        #expect(FileManager.default.fileExists(atPath: managed.path))
    }

    @Test func foldersKeepNamesContentsAndExecutablePermissions() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let folder = fixture.root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let script = folder.appendingPathComponent("run.sh")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let repository = CCRepository(rootURL: fixture.data)
        let record = try repository.addFile(folder)
        #expect(record.kind == .folder)
        let managed = try #require(try repository.contentURL(for: record))
        #expect(managed.lastPathComponent == "Sources")
        let attributes = try FileManager.default.attributesOfItem(atPath: managed.appendingPathComponent("run.sh").path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        try FileManager.default.removeItem(at: folder)
        #expect(try String(contentsOf: managed.appendingPathComponent("run.sh"), encoding: .utf8) == "#!/bin/sh\nexit 0\n")
    }

    @Test func longTextIsStoredWholeAndDeduplicatedOnlyForTheSameSource() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let repository = CCRepository(rootURL: fixture.data)
        let text = String(repeating: "長い資料 👨‍👩‍👧‍👦\nsecond line\tvalue\n", count: 3_000)
        let record = try repository.addText(text, title: "Full material", source: "human")
        #expect(try repository.get(record.id).text == text)
        #expect(try repository.addText(text).id == record.id)
        #expect(try repository.addText(text, source: "claude").id != record.id)
        #expect(try repository.addText(text, title: "Different title").id != record.id)
        #expect(try repository.list().first?.id == record.id)
    }

    @Test func equalFilesReuseSnapshotButChangedFilesCreateNewSnapshots() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("notes.txt")
        try Data("first".utf8).write(to: source)
        let repository = CCRepository(rootURL: fixture.data)
        let first = try repository.addFile(source)
        #expect(try repository.addFile(source).id == first.id)
        #expect(try repository.addFile(source, source: "codex").id != first.id)
        try Data("second".utf8).write(to: source)
        let second = try repository.addFile(source)
        #expect(second.id != first.id)
        let firstURL = try #require(try repository.contentURL(for: first))
        let secondURL = try #require(try repository.contentURL(for: second))
        #expect(try String(contentsOf: firstURL, encoding: .utf8) == "first")
        #expect(try String(contentsOf: secondURL, encoding: .utf8) == "second")
    }

    @Test func newNotesCreateNewHandoffsEvenWhenContentsMatch() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let repository = CCRepository(rootURL: fixture.data)
        let source = fixture.root.appendingPathComponent("notes.txt")
        try Data("same file".utf8).write(to: source)
        let firstFile = try repository.addFile(source, source: "codex", note: "First")
        let secondFile = try repository.addFile(source, source: "codex", note: "Second")
        #expect(firstFile.id != secondFile.id)
        #expect(secondFile.note == "Second")
        let firstText = try repository.addText("same text", source: "claude", note: "First")
        let secondText = try repository.addText("same text", source: "claude", note: "Second")
        #expect(firstText.id != secondText.id)
        let url = try #require(URL(string: "https://example.com/document"))
        let firstLink = try repository.addLink(url, source: "codex", note: "First")
        let secondLink = try repository.addLink(url, source: "codex", note: "Second")
        #expect(firstLink.id != secondLink.id)
        #expect(try repository.addLink(url, source: "codex", note: "Second").id == secondLink.id)
    }

    @Test(arguments: ["grokbot", "review-bot", "Research Bot", "調査アシスタント", String(repeating: "a", count: 64)])
    func customSendersSurviveRestartAndDeduplicateByName(source: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let repository = CCRepository(rootURL: fixture.data)
        let existing = try repository.addText("Existing handoff", source: "codex")
        let file = fixture.root.appendingPathComponent("result.txt")
        try Data("Result".utf8).write(to: file)
        let link = try #require(URL(string: "https://example.com/result"))
        let records = [
            try repository.addFile(file, source: source),
            try repository.addText("Same content", source: source),
            try repository.addLink(link, source: source)
        ]
        #expect(try repository.addFile(file, source: source).id == records[0].id)
        #expect(try repository.addText("Same content", source: source).id == records[1].id)
        #expect(try repository.addLink(link, source: source).id == records[2].id)

        let restarted = CCRepository(rootURL: fixture.data)
        #expect(try restarted.get(existing.id) == existing)
        for record in records {
            #expect(record.source == source)
            #expect(try restarted.get(record.id) == record)
        }
        #expect(try restarted.list().count == 4)
        let human = try restarted.addText("Same content", source: "human")
        #expect(human.id != records[1].id)
        #expect(human.source == "human")
    }

    @Test(arguments: [
        "", " ", " grokbot", "grokbot ", "grok\nbot", "grok\tbot", "grok\u{2028}bot",
        "grok\u{2029}bot", "grok\u{0000}bot", String(repeating: "a", count: 65),
        "e" + String(repeating: "\u{0301}", count: 128)
    ])
    func rejectsMalformedSenderNamesWithoutChangingStoredItems(source: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let repository = CCRepository(rootURL: fixture.data)
        let existing = try repository.addText("Keep this")
        let database = fixture.data.appendingPathComponent("records.json")
        let before = try Data(contentsOf: database)
        let file = fixture.root.appendingPathComponent("result.txt")
        try Data("Result".utf8).write(to: file)
        let link = try #require(URL(string: "https://example.com/result"))
        #expect(throws: CCRepositoryError.self) { try repository.addText("Rejected", source: source) }
        #expect(throws: CCRepositoryError.self) { try repository.addFile(file, source: source) }
        #expect(throws: CCRepositoryError.self) { try repository.addLink(link, source: source) }
        #expect(try Data(contentsOf: database) == before)
        #expect(try repository.list() == [existing])
    }

    @Test func malformedStoredSendersFailClosedWithoutReplacingTheStore() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let repository = CCRepository(rootURL: fixture.data)
        _ = try repository.addText("Keep this", source: "grokbot")
        let database = fixture.data.appendingPathComponent("records.json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: database)) as? [String: Any])
        var records = try #require(object["records"] as? [[String: Any]])
        records[0]["source"] = "bad\nsource"
        object["records"] = records
        let malformed = try JSONSerialization.data(withJSONObject: object)
        try malformed.write(to: database)
        #expect(throws: CCRepositoryError.self) { try repository.list() }
        #expect(throws: CCRepositoryError.self) { try repository.addText("Must not overwrite") }
        #expect(try Data(contentsOf: database) == malformed)
    }

    @Test func rejectsInvalidSourcesIDsAndSymbolicLinks() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let repository = CCRepository(rootURL: fixture.data)
        #expect(throws: CCRepositoryError.self) { try repository.addText("text", source: "bad\nsource") }
        #expect(throws: CCRepositoryError.self) { try repository.get(UUID()) }
        let source = fixture.root.appendingPathComponent("source.txt")
        try Data("private".utf8).write(to: source)
        let symlink = fixture.root.appendingPathComponent("alias.txt")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: source)
        #expect(throws: CCRepositoryError.self) { try repository.addFile(symlink) }
        let folder = fixture.root.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("outside"), withDestinationURL: source)
        #expect(throws: CCRepositoryError.self) { try repository.addFile(folder) }
        #expect(try repository.list().isEmpty)
        #expect(try String(contentsOf: source, encoding: .utf8) == "private")
    }

    @Test func corruptionFailsClosedAndDoesNotOverwriteTheStore() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let repository = CCRepository(rootURL: fixture.data)
        _ = try repository.addText("keep")
        let database = fixture.data.appendingPathComponent("records.json")
        let corrupt = Data("not a cc database".utf8)
        try corrupt.write(to: database)
        #expect(throws: CCRepositoryError.self) { try repository.list() }
        #expect(throws: CCRepositoryError.self) { try repository.addText("must not replace corruption") }
        #expect(throws: CCRepositoryError.self) { try repository.clear() }
        #expect(try Data(contentsOf: database) == corrupt)
    }

    @Test func rejectsPathEscapesAndForgedRecords() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let repository = CCRepository(rootURL: fixture.data)
        let source = fixture.root.appendingPathComponent("file.txt")
        try Data("owned".utf8).write(to: source)
        let record = try repository.addFile(source)
        let forged = CCRecord(
            id: record.id, kind: record.kind, title: record.title, source: record.source,
            createdAt: record.createdAt, originalPath: source.path, relativePath: "../../file.txt"
        )
        #expect(throws: CCRepositoryError.self) { try repository.contentURL(for: forged) }
        let database = fixture.data.appendingPathComponent("records.json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: database)) as? [String: Any])
        var records = try #require(object["records"] as? [[String: Any]])
        records[0]["relativePath"] = "../../file.txt"
        object["records"] = records
        let corrupted = try JSONSerialization.data(withJSONObject: object)
        try corrupted.write(to: database)
        #expect(throws: CCRepositoryError.self) { try repository.list() }
        #expect(try Data(contentsOf: database) == corrupted)
        #expect(try String(contentsOf: source, encoding: .utf8) == "owned")
    }

    @Test func missingOrReplacedPayloadsRemainListedButCannotBeRetrieved() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let repository = CCRepository(rootURL: fixture.data)
        let source = fixture.root.appendingPathComponent("original.txt")
        try Data("original".utf8).write(to: source)
        let record = try repository.addFile(source)
        let managed = try #require(try repository.contentURL(for: record))
        try FileManager.default.removeItem(at: managed)
        #expect(try repository.list() == [record])
        #expect(try repository.contentURLs(for: [record]).isEmpty)
        #expect(throws: CCRepositoryError.self) { try repository.get(record.id) }
        try FileManager.default.createSymbolicLink(at: managed, withDestinationURL: source)
        #expect(throws: CCRepositoryError.self) { try repository.get(record.id) }
        try repository.remove(record.id)
        #expect(try String(contentsOf: source, encoding: .utf8) == "original")
    }

    @Test func storageDirectoriesAndMetadataArePrivate() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let repository = CCRepository(rootURL: fixture.data)
        _ = try repository.addText("private note")
        let directory = try FileManager.default.attributesOfItem(atPath: fixture.data.path)
        let metadata = try FileManager.default.attributesOfItem(atPath: fixture.data.appendingPathComponent("records.json").path)
        #expect((directory[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        #expect((metadata[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func concurrentCLIProcessesHonorTheLockAndKeepAllWrites() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let repository = CCRepository(rootURL: fixture.data)
        _ = try repository.list()
        let executable = try cliExecutable()
        let descriptor = Darwin.open(fixture.data.appendingPathComponent(".lock").path, O_RDWR)
        #expect(descriptor >= 0)
        guard descriptor >= 0 else { return }
        defer { Darwin.close(descriptor) }
        #expect(testFlock(descriptor, LOCK_EX) == 0)
        var processes: [Process] = []
        for index in 0..<6 {
            let process = Process()
            process.executableURL = executable
            process.arguments = ["add", "--text", "writer \(index)\n" + String(repeating: "material", count: 500), "--source", "codex"]
            var environment = ProcessInfo.processInfo.environment
            environment["CC_DATA_DIR"] = fixture.data.path
            process.environment = environment
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try process.run()
            processes.append(process)
        }
        try await Task.sleep(for: .milliseconds(250))
        #expect(processes.allSatisfy { $0.isRunning })
        #expect(testFlock(descriptor, LOCK_UN) == 0)
        for process in processes {
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
        }
        let records = try repository.list()
        #expect(records.count == 6)
        #expect(Set(records.map(\.id)).count == 6)
        for index in 0..<6 {
            #expect(records.contains { $0.text?.hasPrefix("writer \(index)\n") == true })
        }
    }

    @Test func CLIHelpUsesTheShelfCommandName() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let executable = try cliExecutable()
        for argument in ["help", "--help", "-h"] {
            let response = try runCLI(executable, arguments: [argument], data: fixture.data)
            #expect(response.status == 0)
            #expect(response.error.isEmpty)
            let help = try #require(String(data: response.output, encoding: .utf8))
            #expect(help.contains("cc-shelf list\n"))
            #expect(help.contains("cc-shelf add PATH "))
            #expect(help.contains("cc-shelf add --text "))
            #expect(help.contains("cc-shelf get UUID "))
        }
    }

    @Test func CLIArgumentErrorsKeepJSONAndUseTheShelfCommandName() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let executable = try cliExecutable()
        let cases: [(arguments: [String], code: String, guidance: String)] = [
            ([], "usage", "cc-shelf --help"),
            (["unknown-command"], "unknown_command", "cc-shelf --help"),
            (["get", "not-an-id"], "invalid_id", "cc-shelf list"),
        ]
        for example in cases {
            let response = try runCLI(executable, arguments: example.arguments, data: fixture.data)
            #expect(response.status != 0)
            #expect(response.output.isEmpty)
            let envelope = try #require(JSONSerialization.jsonObject(with: response.error) as? [String: Any])
            #expect(envelope["ok"] as? Bool == false)
            let error = try #require(envelope["error"] as? [String: Any])
            #expect(error["code"] as? String == example.code)
            let message = try #require(error["message"] as? String)
            #expect(message.contains(example.guidance))
        }
    }

    @Test func CLIStoresSenderNamesForFilesTextAndStandardInput() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let executable = try cliExecutable()
        let file = fixture.root.appendingPathComponent("result.txt")
        try Data("File result".utf8).write(to: file)
        let cases: [(arguments: [String], input: Data?, source: String)] = [
            (["add", file.path, "--source", "grokbot"], nil, "grokbot"),
            (["add", "--text", "Custom sender result", "--source", "調査 Bot"], nil, "調査 Bot"),
            (["add", "--stdin", "--source", "grokbot"], Data("Standard input result".utf8), "grokbot"),
            (["add", "--text", "Manual result"], nil, "human")
        ]
        let repository = CCRepository(rootURL: fixture.data)
        for example in cases {
            let response = try runCLI(executable, arguments: example.arguments, data: fixture.data, input: example.input)
            #expect(response.status == 0)
            #expect(response.error.isEmpty)
            let envelope = try #require(JSONSerialization.jsonObject(with: response.output) as? [String: Any])
            #expect(envelope["ok"] as? Bool == true)
            let item = try #require(envelope["item"] as? [String: Any])
            #expect(item["source"] as? String == example.source)
            let id = try #require((item["id"] as? String).flatMap(UUID.init(uuidString:)))
            #expect(try repository.get(id).source == example.source)
        }
        #expect(try repository.list().count == cases.count)
        let rejected = try runCLI(executable, arguments: ["add", "--text", "Rejected", "--source", "bad\nsource"], data: fixture.data)
        #expect(rejected.status != 0)
        let envelope = try #require(JSONSerialization.jsonObject(with: rejected.error) as? [String: Any])
        #expect((envelope["error"] as? [String: Any])?["code"] as? String == "invalid_source")
        #expect(try repository.list().count == cases.count)
    }

    @Test func CLIReadsFullTextAndNeverOverwritesOutput() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let repository = CCRepository(rootURL: fixture.data)
        let text = String(repeating: "全文\nspaces\tand 👩‍💻\n", count: 1_000)
        let record = try repository.addText(text)
        let executable = try cliExecutable()
        let read = try runCLI(executable, arguments: ["get", record.id.uuidString, "--text"], data: fixture.data)
        #expect(read.status == 0)
        #expect(String(data: read.output, encoding: .utf8) == text)
        let metadata = try runCLI(executable, arguments: ["get", record.id.uuidString], data: fixture.data)
        let envelope = try #require(JSONSerialization.jsonObject(with: metadata.output) as? [String: Any])
        let item = try #require(envelope["item"] as? [String: Any])
        #expect(item["text"] == nil)
        let target = fixture.root.appendingPathComponent("export.txt")
        let copy = try runCLI(executable, arguments: ["get", record.id.uuidString, "--output", target.path], data: fixture.data)
        #expect(copy.status == 0)
        #expect(try String(contentsOf: target, encoding: .utf8) == text)
        let duplicate = try runCLI(executable, arguments: ["get", record.id.uuidString, "--output", target.path], data: fixture.data)
        #expect(duplicate.status != 0)
        #expect(duplicate.output.isEmpty)
        #expect(try String(contentsOf: target, encoding: .utf8) == text)
        let error = try #require(JSONSerialization.jsonObject(with: duplicate.error) as? [String: Any])
        #expect(error["ok"] as? Bool == false)
        #expect((error["error"] as? [String: Any])?["code"] as? String == "output_exists")
        let invalidID = try runCLI(executable, arguments: ["get", "not-an-id"], data: fixture.data)
        #expect(invalidID.status != 0)
        #expect(invalidID.output.isEmpty)
    }

    private struct Fixture {
        let root: URL
        var data: URL { root.appendingPathComponent("data", isDirectory: true) }

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("CCCoreTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    private func cliExecutable() throws -> URL {
        var candidates: [URL] = []
        if let path = ProcessInfo.processInfo.environment["CC_CLI_TEST_BINARY"] {
            candidates.append(URL(fileURLWithPath: path))
        }
        for initial in [Bundle.main.bundleURL, URL(fileURLWithPath: CommandLine.arguments[0])] {
            var directory = initial.deletingLastPathComponent()
            for _ in 0..<5 {
                candidates.append(directory.appendingPathComponent("cc-shelf"))
                directory.deleteLastPathComponent()
            }
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        candidates.append(root.appendingPathComponent(".build/debug/cc-shelf"))
        return try #require(candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }, "Build the cc-shelf CLI, or set CC_CLI_TEST_BINARY, to run cross-process tests.")
    }

    private func runCLI(_ executable: URL, arguments: [String], data: URL, input: Data? = nil) throws -> (status: Int32, output: Data, error: Data) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["CC_DATA_DIR"] = data.path
        process.environment = environment
        let output = Pipe()
        let error = Pipe()
        let standardInput = Pipe()
        process.standardOutput = output
        process.standardError = error
        process.standardInput = input == nil ? FileHandle.nullDevice : standardInput
        try process.run()
        if let input {
            try standardInput.fileHandleForWriting.write(contentsOf: input)
            try standardInput.fileHandleForWriting.close()
        }
        let bytes = output.fileHandleForReading.readDataToEndOfFile()
        let errors = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, bytes, errors)
    }
}
