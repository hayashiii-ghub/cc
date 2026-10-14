import ContextCore
import Foundation

@main
struct ContextCLI {
    static func main() {
        do {
            try run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            let failure = error as? ContextRepositoryError
                ?? ContextRepositoryError(code: "io_error", message: error.localizedDescription)
            emit(ErrorEnvelope(ok: false, error: failure), to: .standardError)
            exit(1)
        }
    }

    private static func run(_ arguments: [String]) throws {
        guard let command = arguments.first else { throw usage() }
        let repository = ContextRepository()
        let arguments = Array(arguments.dropFirst())
        switch command {
        case "list":
            guard arguments.isEmpty else { throw usage() }
            let items = try repository.list().map { CLIItem(record: $0, path: nil, includesText: false) }
            emit(ItemsEnvelope(ok: true, items: items))
        case "add":
            let options = try AddOptions(arguments)
            let record: ContextRecord
            if let path = options.path {
                record = try repository.addFile(URL(fileURLWithPath: path), source: options.source, note: options.note)
            } else {
                let text: String
                if options.stdin {
                    guard let value = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) else {
                        throw ContextRepositoryError(code: "invalid_input", message: "Standard input must contain UTF-8 text.")
                    }
                    text = value
                } else {
                    text = options.text ?? ""
                }
                record = try repository.addText(text, title: options.title, source: options.source, note: options.note)
            }
            let path = try repository.contentURL(for: record)?.path
            emit(ItemEnvelope(ok: true, item: CLIItem(record: record, path: path)))
        case "get":
            let options = try GetOptions(arguments)
            let record = try repository.get(options.id)
            let contentURL = try repository.contentURL(for: record)
            if options.text {
                guard let text = record.text else {
                    throw ContextRepositoryError(code: "not_text", message: "This item is a file or folder. Use get or get --output instead.")
                }
                FileHandle.standardOutput.write(Data(text.utf8))
            } else {
                if let output = options.output {
                    try export(record: record, contentURL: contentURL, to: URL(fileURLWithPath: output))
                }
                emit(ItemEnvelope(ok: true, item: CLIItem(record: record, path: contentURL?.path)))
            }
        case "--help", "help", "-h":
            FileHandle.standardOutput.write(Data((
                "cc: — local shelf\n\ncontext list\n"
                + "context add PATH [--source human|codex|claude] [--note TEXT]\n"
                + "context add --text TEXT|--stdin [--title TEXT] [--source human|codex|claude] [--note TEXT]\n"
                + "context get UUID [--text | --output PATH]\n"
            ).utf8))
        default:
            throw ContextRepositoryError(code: "unknown_command", message: "Unknown command. Use context --help.")
        }
    }

    private static func export(record: ContextRecord, contentURL: URL?, to output: URL) throws {
        do {
            _ = try FileManager.default.attributesOfItem(atPath: output.path)
            throw ContextRepositoryError(code: "output_exists", message: "The output path already exists. cc: will not overwrite it.")
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            // The output must be a new path so existing documents remain untouched.
        }
        if let contentURL {
            try FileManager.default.copyItem(at: contentURL, to: output)
        } else if let text = record.text {
            try Data(text.utf8).write(to: output, options: .withoutOverwriting)
        } else {
            throw ContextRepositoryError(code: "missing_content", message: "The registered item has no content to copy.")
        }
    }

    private static func usage() -> ContextRepositoryError {
        ContextRepositoryError(code: "usage", message: "Invalid arguments. Use context --help.")
    }

    private static func emit<T: Encodable>(_ value: T, to handle: FileHandle = .standardOutput) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            var data = try encoder.encode(value)
            data.append(10)
            handle.write(data)
        } catch {
            FileHandle.standardError.write(Data("{\"ok\":false,\"error\":{\"code\":\"encoding_error\",\"message\":\"Could not encode cc: response.\"}}\n".utf8))
            exit(1)
        }
    }

    private struct AddOptions {
        var path: String?
        var text: String?
        var stdin = false
        var title: String?
        var source = "human"
        var note: String?

        init(_ arguments: [String]) throws {
            var index = 0
            var positionalOnly = false
            var seen = Set<String>()
            while index < arguments.count {
                let argument = arguments[index]
                index += 1
                if !positionalOnly, argument == "--" { positionalOnly = true; continue }
                if !positionalOnly, argument.hasPrefix("--") {
                    guard seen.insert(argument).inserted else { throw usage() }
                    if argument == "--stdin" { stdin = true; continue }
                    guard ["--text", "--title", "--source", "--note"].contains(argument),
                          index < arguments.count else { throw usage() }
                    let value = arguments[index]
                    index += 1
                    switch argument {
                    case "--text": text = value
                    case "--title": title = value
                    case "--source": source = value
                    case "--note": note = value
                    default: break
                    }
                } else {
                    guard path == nil else { throw usage() }
                    path = argument
                }
            }
            let inputCount = (path == nil ? 0 : 1) + (text == nil ? 0 : 1) + (stdin ? 1 : 0)
            guard inputCount == 1, path == nil || title == nil else { throw usage() }
        }
    }

    private struct GetOptions {
        let id: UUID
        var text = false
        var output: String?

        init(_ arguments: [String]) throws {
            guard let value = arguments.first else { throw usage() }
            guard let id = UUID(uuidString: value) else {
                throw ContextRepositoryError(code: "invalid_id", message: "The item ID must be a UUID from context list.")
            }
            self.id = id
            var index = 1
            while index < arguments.count {
                let argument = arguments[index]
                index += 1
                if argument == "--text", !text, output == nil {
                    text = true
                } else if argument == "--output", !text, output == nil, index < arguments.count {
                    output = arguments[index]
                    index += 1
                } else {
                    throw usage()
                }
            }
        }
    }

    private struct CLIItem: Encodable {
        let record: ContextRecord
        let path: String?
        var includesText = false

        enum CodingKeys: String, CodingKey {
            case id, kind, title, text, source, note, createdAt, originalPath, relativePath, path
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(record.id, forKey: .id)
            try container.encode(record.kind, forKey: .kind)
            try container.encode(record.title, forKey: .title)
            if includesText { try container.encodeIfPresent(record.text, forKey: .text) }
            try container.encode(record.source, forKey: .source)
            try container.encodeIfPresent(record.note, forKey: .note)
            try container.encode(record.createdAt, forKey: .createdAt)
            try container.encodeIfPresent(record.originalPath, forKey: .originalPath)
            try container.encodeIfPresent(record.relativePath, forKey: .relativePath)
            try container.encodeIfPresent(path, forKey: .path)
        }
    }

    private struct ItemEnvelope: Encodable {
        let ok: Bool
        let item: CLIItem
    }

    private struct ItemsEnvelope: Encodable {
        let ok: Bool
        let items: [CLIItem]
    }

    private struct ErrorEnvelope: Encodable {
        let ok: Bool
        let error: ContextRepositoryError
    }
}
