import Foundation

public enum CCItemKind: String, Codable, Equatable, Sendable {
    case file
    case folder
    case image
    case link
    case text
}

public struct CCRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let kind: CCItemKind
    public let title: String
    public let text: String?
    public let source: String
    public let note: String?
    public let createdAt: Date
    public let originalPath: String?
    public let relativePath: String?

    public init(
        id: UUID,
        kind: CCItemKind,
        title: String,
        text: String? = nil,
        source: String,
        note: String? = nil,
        createdAt: Date,
        originalPath: String? = nil,
        relativePath: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.text = text
        self.source = source
        self.note = note
        self.createdAt = createdAt
        self.originalPath = originalPath
        self.relativePath = relativePath
    }
}

public struct CCRepositoryError: Error, LocalizedError, Codable, Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }

    public var errorDescription: String? { message }
}
