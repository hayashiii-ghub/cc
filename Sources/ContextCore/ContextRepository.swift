import Darwin
import Foundation

// Darwin exposes the flock struct under the same name as the C lock function.
@_silgen_name("flock")
private func contextFlock(_ descriptor: Int32, _ operation: Int32) -> Int32

public struct ContextRepository: Sendable {
    public let rootURL: URL

    public static var defaultRootURL: URL {
        if let directory = ProcessInfo.processInfo.environment["CONTEXT_DATA_DIR"], !directory.isEmpty {
            return URL(fileURLWithPath: directory, isDirectory: true).standardizedFileURL
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("Context", isDirectory: true)
    }

    public init(rootURL: URL = ContextRepository.defaultRootURL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    public func list() throws -> [ContextRecord] {
        try transaction { try readDatabase().records }
    }

    public func get(_ id: UUID) throws -> ContextRecord {
        let record = try transaction { try registeredRecord(id, in: readDatabase()) }
        _ = try managedContentURL(record)
        return record
    }

    public func contentURL(for record: ContextRecord) throws -> URL? {
        let registered = try transaction {
            let registered = try registeredRecord(record.id, in: readDatabase())
            guard registered == record else {
                throw failure("invalid_record", "The item does not match its registered snapshot.")
            }
            return registered
        }
        return try managedContentURL(registered)
    }

    public func contentURLs(for records: [ContextRecord]) throws -> [UUID: URL] {
        let registered = try transaction {
            Dictionary(uniqueKeysWithValues: try readDatabase().records.map { ($0.id, $0) })
        }
        var result: [UUID: URL] = [:]
        for record in records where record.relativePath != nil && registered[record.id] == record {
            if let url = try? managedContentURL(record, validatesTree: false) {
                result[record.id] = url
            }
        }
        return result
    }

    public func addFile(_ url: URL, source: String = "human", note: String? = nil) throws -> ContextRecord {
        try validateSource(source)
        guard url.isFileURL else { throw failure("invalid_input", "Add a local file or folder.") }
        let sourceURL = url.standardizedFileURL
        try validateSourceTree(sourceURL)
        let name = sourceURL.lastPathComponent
        guard !name.isEmpty, name != "/", name != ".", name != ".." else {
            throw failure("invalid_input", "The file or folder needs a name.")
        }

        let id = UUID()
        let directory = assetDirectory(id)
        let candidates = try transaction {
            let records = try readDatabase().records
            try ensurePrivateDirectory(directory)
            return records.filter { $0.source == source && $0.title == name && $0.note == note && $0.relativePath != nil }
        }
        let destination = directory.appendingPathComponent(name)
        var committed = false
        defer {
            if !committed { try? FileManager.default.removeItem(at: directory) }
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        try validateSourceTree(destination)
        try protectTree(destination)
        let duplicateIDs = Set(candidates.compactMap { record -> UUID? in
            guard let existing = try? managedContentURL(record),
                  FileManager.default.contentsEqual(atPath: existing.path, andPath: destination.path) else { return nil }
            return record.id
        })
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        let kind: ContextItemKind = attributes[.type] as? FileAttributeType == .typeDirectory
            ? .folder : (Self.imageExtensions.contains(destination.pathExtension.lowercased()) ? .image : .file)

        return try transaction {
            var database = try readDatabase()
            if let existing = database.records.first(where: { duplicateIDs.contains($0.id) }) {
                return existing
            }
            let record = ContextRecord(
                id: id,
                kind: kind,
                title: name,
                source: source,
                note: note,
                createdAt: Date(),
                originalPath: sourceURL.path,
                relativePath: "assets/\(id.uuidString)/\(name)"
            )
            database.records.append(record)
            try writeDatabase(database)
            committed = true
            return record
        }
    }

    public func addText(
        _ text: String,
        title: String? = nil,
        source: String = "human",
        note: String? = nil
    ) throws -> ContextRecord {
        try validateSource(source)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw failure("invalid_input", "Text must not be empty.")
        }
        let resolvedTitle: String
        if let title {
            let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { throw failure("invalid_input", "The title must not be empty.") }
            resolvedTitle = value
        } else {
            let line = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? "Text"
            resolvedTitle = String(line.prefix(80))
        }

        return try transaction {
            var database = try readDatabase()
            if let existing = database.records.first(where: {
                $0.kind == .text && $0.text == text && $0.source == source && $0.note == note
                    && (title == nil || $0.title == resolvedTitle)
            }) {
                return existing
            }
            let record = ContextRecord(
                id: UUID(), kind: .text, title: resolvedTitle, text: text,
                source: source, note: note, createdAt: Date()
            )
            database.records.append(record)
            try writeDatabase(database)
            return record
        }
    }

    public func addLink(_ url: URL, source: String = "human", note: String? = nil) throws -> ContextRecord {
        try validateSource(source)
        guard url.scheme != nil, !url.isFileURL else {
            throw failure("invalid_input", "Use an absolute link, or add a local file.")
        }
        return try transaction {
            var database = try readDatabase()
            if let existing = database.records.first(where: {
                $0.kind == .link && $0.text == url.absoluteString && $0.source == source && $0.note == note
            }) {
                return existing
            }
            let record = ContextRecord(
                id: UUID(), kind: .link, title: url.host(percentEncoded: false) ?? url.absoluteString,
                text: url.absoluteString, source: source, note: note, createdAt: Date()
            )
            database.records.append(record)
            try writeDatabase(database)
            return record
        }
    }

    public func remove(_ id: UUID) throws {
        try transaction {
            var database = try readDatabase()
            let record = try registeredRecord(id, in: database)
            try deleting(records: [record]) {
                database.records.removeAll { $0.id == id }
                try writeDatabase(database)
            }
        }
    }

    public func clear() throws {
        try transaction {
            let database = try readDatabase()
            try deleting(records: database.records) { try writeDatabase(Database(records: [])) }
        }
    }

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "tif", "tiff", "heic", "heif", "webp", "svg", "bmp", "avif", "ico"
    ]

    private struct Database: Codable {
        var schemaVersion = 1
        var records: [ContextRecord]
    }

    private var recordsURL: URL { rootURL.appendingPathComponent("records.json") }
    private var assetsURL: URL { rootURL.appendingPathComponent("assets", isDirectory: true) }

    private func assetDirectory(_ id: UUID) -> URL {
        assetsURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func failure(_ code: String, _ message: String) -> ContextRepositoryError {
        ContextRepositoryError(code: code, message: message)
    }

    private func validateSource(_ source: String) throws {
        guard ["human", "codex", "claude"].contains(source) else {
            throw failure("invalid_source", "Source must be human, codex, or claude.")
        }
    }

    private func transaction<T>(_ body: () throws -> T) throws -> T {
        do {
            guard rootURL.isFileURL else { throw failure("invalid_input", "The data directory must be local.") }
            try ensurePrivateDirectory(rootURL)
            try ensurePrivateDirectory(assetsURL)
            let lockURL = rootURL.appendingPathComponent(".lock")
            let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            defer { Darwin.close(descriptor) }
            guard Darwin.fchmod(descriptor, 0o600) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            while contextFlock(descriptor, LOCK_EX) != 0 {
                guard errno == EINTR else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            }
            defer { _ = contextFlock(descriptor, LOCK_UN) }
            return try body()
        } catch let error as ContextRepositoryError {
            throw error
        } catch {
            throw failure("io_error", error.localizedDescription)
        }
    }

    private func ensurePrivateDirectory(_ url: URL) throws {
        if let attributes = try attributesIfPresent(url) {
            guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                throw failure("unsafe_path", "A cc: storage directory is not a regular directory.")
            }
        } else {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private func attributesIfPresent(_ url: URL) throws -> [FileAttributeKey: Any]? {
        do {
            return try FileManager.default.attributesOfItem(atPath: url.path)
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    private func readDatabase() throws -> Database {
        guard let attributes = try attributesIfPresent(recordsURL) else { return Database(records: []) }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw failure("corrupt_store", "cc: records are not a regular file. The store was kept unchanged.")
        }
        let data = try Data(contentsOf: recordsURL)
        let database: Database
        do {
            database = try JSONDecoder().decode(Database.self, from: data)
        } catch {
            throw failure("corrupt_store", "cc: records are invalid. The store was kept unchanged.")
        }
        guard database.schemaVersion == 1 else {
            throw failure("unsupported_schema", "This cc: data version is unsupported. The store was kept unchanged.")
        }
        guard Set(database.records.map(\.id)).count == database.records.count else {
            throw failure("corrupt_store", "cc: records contain duplicate IDs. The store was kept unchanged.")
        }
        for record in database.records {
            do { try validateRecord(record) } catch {
                throw failure("corrupt_store", "cc: item metadata is invalid. The store was kept unchanged.")
            }
        }
        return database
    }

    private func registeredRecord(_ id: UUID, in database: Database) throws -> ContextRecord {
        guard let record = database.records.first(where: { $0.id == id }) else {
            throw failure("not_found", "No registered cc: item has that ID.")
        }
        return record
    }

    private func validateRecord(_ record: ContextRecord) throws {
        try validateSource(record.source)
        guard !record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              record.createdAt.timeIntervalSinceReferenceDate.isFinite else {
            throw failure("invalid_record", "Invalid cc: item metadata.")
        }
        switch record.kind {
        case .file, .folder, .image:
            guard let relativePath = record.relativePath else { throw failure("invalid_record", "Missing managed path.") }
            let components = relativePath.components(separatedBy: "/")
            guard components.count == 3, components[0] == "assets",
                  components[1] == record.id.uuidString, components[2] == record.title,
                  !components[2].isEmpty, components[2] != ".", components[2] != "..",
                  record.text == nil else { throw failure("unsafe_path", "Invalid managed snapshot path.") }
        case .text:
            guard record.relativePath == nil, record.originalPath == nil,
                  let text = record.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw failure("invalid_record", "Invalid stored text.")
            }
        case .link:
            guard record.relativePath == nil, record.originalPath == nil,
                  let text = record.text, let url = URL(string: text), url.scheme != nil, !url.isFileURL else {
                throw failure("invalid_record", "Invalid stored link.")
            }
        }
    }

    private func managedContentURL(_ record: ContextRecord, validatesTree: Bool = true) throws -> URL? {
        try validateRecord(record)
        guard record.relativePath != nil else { return nil }
        let directory = assetDirectory(record.id)
        guard let attributes = try attributesIfPresent(directory),
              attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw failure("missing_content", "The registered snapshot is missing or unsafe.")
        }
        let url = directory.appendingPathComponent(record.title)
        guard let attributes = try attributesIfPresent(url) else {
            throw failure("missing_content", "The registered snapshot is missing.")
        }
        let expected: FileAttributeType = record.kind == .folder ? .typeDirectory : .typeRegular
        guard attributes[.type] as? FileAttributeType == expected else {
            throw failure("unsafe_path", "The registered snapshot is not the expected file or folder.")
        }
        if validatesTree { try validateSourceTree(url) }
        return url
    }

    private func validateSourceTree(_ url: URL) throws {
        guard let attributes = try attributesIfPresent(url) else {
            throw failure("not_found", "The file or folder does not exist.")
        }
        let type = attributes[.type] as? FileAttributeType
        guard type == .typeRegular || type == .typeDirectory else {
            throw failure("unsafe_path", "cc: accepts regular files and folders without symbolic links.")
        }
        if type == .typeDirectory {
            var enumerationError: Error?
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: nil,
                errorHandler: { _, error in enumerationError = error; return false }
            ) else { throw failure("io_error", "The folder could not be read.") }
            for case let child as URL in enumerator {
                let type = try FileManager.default.attributesOfItem(atPath: child.path)[.type] as? FileAttributeType
                guard type == .typeRegular || type == .typeDirectory else {
                    throw failure("unsafe_path", "Folders must not contain symbolic links or special files.")
                }
            }
            if let enumerationError { throw enumerationError }
        }
    }

    private func protectTree(_ url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let type = attributes[.type] as? FileAttributeType
        try setPrivatePermissions(url, attributes: attributes)
        if type == .typeDirectory,
           let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
            for case let child as URL in enumerator {
                let attributes = try FileManager.default.attributesOfItem(atPath: child.path)
                try setPrivatePermissions(child, attributes: attributes)
            }
        }
    }

    private func setPrivatePermissions(_ url: URL, attributes: [FileAttributeKey: Any]) throws {
        let permissions: Int
        if attributes[.type] as? FileAttributeType == .typeDirectory {
            permissions = 0o700
        } else {
            let original = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
            permissions = 0o600 | (original & 0o100)
        }
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }

    private func writeDatabase(_ database: Database) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(database)
        let temporary = rootURL.appendingPathComponent(".records-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard FileManager.default.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw failure("io_error", "The cc: records file could not be written.")
        }
        let handle = try FileHandle(forWritingTo: temporary)
        do { try handle.synchronize(); try handle.close() } catch { try? handle.close(); throw error }
        guard Darwin.rename(temporary.path, recordsURL.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func deleting(records: [ContextRecord], commit: () throws -> Void) throws {
        try commit()
        var failedCleanup = false
        for record in records where record.relativePath != nil {
            let directory = assetDirectory(record.id)
            do {
                guard try attributesIfPresent(directory) != nil else { continue }
                try FileManager.default.removeItem(at: directory)
            } catch {
                failedCleanup = true
            }
        }
        if failedCleanup {
            throw failure("cleanup_failed", "Removed from the shelf; saved-copy cleanup failed. Original files were not changed.")
        }
    }
}
