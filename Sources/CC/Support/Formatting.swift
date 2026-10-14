import Foundation

extension Date {
    func compactTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: self)
    }
}

extension String {
    func firstMeaningfulLine(limit: Int) -> String {
        let line = components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""

        if line.count <= limit {
            return line
        }

        return String(line.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func sanitizedFileName(defaultName: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
            .union(.newlines)
            .union(.controlCharacters)
        let components = self.components(separatedBy: invalidCharacters)
        let cleaned = components.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.isEmpty || cleaned == "." || cleaned == ".." ? defaultName : cleaned
    }
}

extension URL {
    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    func availableChildURL(named requestedName: String) -> URL {
        let fileManager = FileManager.default
        let safeName = requestedName.sanitizedFileName(defaultName: "Item")
        let baseURL = appendingPathComponent(safeName)

        if !fileManager.fileExists(atPath: baseURL.path) {
            return baseURL
        }

        let baseName = baseURL.deletingPathExtension().lastPathComponent
        let pathExtension = baseURL.pathExtension

        for index in 2...999 {
            let candidateName: String
            if pathExtension.isEmpty {
                candidateName = "\(baseName) \(index)"
            } else {
                candidateName = "\(baseName) \(index).\(pathExtension)"
            }

            let candidateURL = appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return appendingPathComponent("\(baseName)-\(UUID().uuidString)")
    }
}

extension ShelfItem {
    var displayTitle: String {
        if kind == .file || kind == .folder || kind == .image {
            return url?.lastPathComponent ?? title
        }

        return title
    }

    func preferredFileName(fallback: String) -> String {
        if kind == .file || kind == .folder || kind == .image {
            return url?.lastPathComponent.sanitizedFileName(defaultName: fallback) ?? fallback
        }

        let cleanedTitle = title.sanitizedFileName(defaultName: fallback)
        guard let sourceExtension = url?.pathExtension, !sourceExtension.isEmpty else {
            return cleanedTitle
        }

        if cleanedTitle.hasSuffix(".\(sourceExtension)") {
            return cleanedTitle
        }

        return "\(cleanedTitle).\(sourceExtension)"
    }
}
