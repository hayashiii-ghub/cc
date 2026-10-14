import Foundation

enum ShelfItemKind: Sendable {
    case file
    case folder
    case link
    case text
    case image

    var systemImage: String {
        switch self {
        case .file:
            "doc"
        case .folder:
            "folder"
        case .link:
            "link"
        case .text:
            "text.alignleft"
        case .image:
            "photo"
        }
    }
}

enum ShelfItemSecondaryAction: Equatable {
    case copy
    case reveal

    var systemImage: String {
        switch self {
        case .copy:
            "doc.on.clipboard"
        case .reveal:
            "magnifyingglass"
        }
    }

    var help: String {
        switch self {
        case .copy:
            "Copy"
        case .reveal:
            "Reveal"
        }
    }
}

struct ShelfItem: Identifiable, Equatable, Sendable {
    var id: UUID
    var kind: ShelfItemKind
    var title: String
    var detail: String
    var url: URL?
    var text: String?
    var source: String
    var note: String?
    var createdAt: Date
    var isManagedFile: Bool

    init(
        id: UUID = UUID(),
        kind: ShelfItemKind,
        title: String,
        detail: String,
        url: URL? = nil,
        text: String? = nil,
        source: String = "human",
        note: String? = nil,
        createdAt: Date = Date(),
        isManagedFile: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.url = url
        self.text = text
        self.source = source
        self.note = note
        self.createdAt = createdAt
        self.isManagedFile = isManagedFile
    }

    var secondaryAction: ShelfItemSecondaryAction {
        switch kind {
        case .file, .folder, .image:
            .reveal
        case .link, .text:
            .copy
        }
    }
}
