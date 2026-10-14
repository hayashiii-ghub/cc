import AppKit
import Foundation
import UniformTypeIdentifiers

enum ShelfImportResult {
    case file(url: URL, isManaged: Bool)
    case link(URL)
    case text(String)
    case failure(Error)
}

private struct ShelfImportError: LocalizedError {
    var errorDescription: String? { "Could not read the dropped item. Try adding the file from Finder." }
}

struct ShelfItemImporter {
    private static let documentTypeIdentifiers = [
        "net.daringfireball.markdown",
        "public.html"
    ]

    private static let textTypeIdentifiers = [
        UTType.utf8PlainText.identifier,
        UTType.plainText.identifier,
        UTType.text.identifier
    ]

    private static let imageTypeIdentifiers = [
        UTType.png.identifier,
        UTType.tiff.identifier,
        "public.jpeg",
        "com.compuserve.gif",
        "public.heic",
        "public.heif",
        "public.svg-image",
        "com.adobe.svg",
        "org.webmproject.webp"
    ]

    static let acceptedTypeIdentifiers = [
        UTType.fileURL.identifier,
        UTType.url.identifier,
        UTType.image.identifier,
        UTType.item.identifier,
        UTType.data.identifier
    ] + textTypeIdentifiers + documentTypeIdentifiers + imageTypeIdentifiers

    private let inbox: ShelfInbox

    init(inbox: ShelfInbox) {
        self.inbox = inbox
    }

    func importItem(
        from provider: NSItemProvider,
        completion: @escaping (ShelfImportResult) -> Void
    ) {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                guard let url = Self.url(from: item) else {
                    completion(.failure(error ?? ShelfImportError()))
                    return
                }
                completion(.file(url: url, isManaged: false))
            }
            return
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
                guard let url = Self.url(from: item) else {
                    completion(.failure(error ?? ShelfImportError()))
                    return
                }
                completion(.link(url))
            }
            return
        }

        let fileTypeIdentifiers = Self.fileTypeIdentifiers(from: provider)
        if let suggestedName = provider.suggestedName,
           !suggestedName.isEmpty,
           !fileTypeIdentifiers.isEmpty {
            importFileRepresentation(
                from: provider,
                typeIdentifiers: fileTypeIdentifiers,
                requestedName: suggestedName,
                completion: completion
            )
            return
        }

        if let typeIdentifier = Self.documentTypeIdentifiers.first(where: {
            provider.hasItemConformingToTypeIdentifier($0)
        }) {
            let fileExtension = Self.documentFileExtension(for: typeIdentifier)
            importFileRepresentation(
                from: provider,
                typeIdentifiers: ArraySlice([typeIdentifier]),
                requestedName: "Document-\(Date().compactTimestamp()).\(fileExtension)",
                completion: completion
            )
            return
        }

        let imageTypes = Self.imageTypeIdentifiers + [UTType.image.identifier]
        if let typeIdentifier = imageTypes.first(where: {
            provider.hasItemConformingToTypeIdentifier($0)
        }) {
            let fileExtension = Self.imageFileExtension(for: typeIdentifier)
            importFileRepresentation(
                from: provider,
                typeIdentifiers: ArraySlice([typeIdentifier]),
                requestedName: "Image-\(Date().compactTimestamp()).\(fileExtension)",
                completion: completion
            )
            return
        }

        if let typeIdentifier = Self.textTypeIdentifiers.first(where: {
            provider.hasItemConformingToTypeIdentifier($0)
        }) {
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                guard let text = Self.text(from: item) else {
                    completion(.failure(error ?? ShelfImportError()))
                    return
                }
                completion(.text(text))
            }
            return
        }

        guard let typeIdentifier = fileTypeIdentifiers.first else {
            completion(.failure(ShelfImportError()))
            return
        }
        importFileRepresentation(
            from: provider,
            typeIdentifiers: fileTypeIdentifiers,
            requestedName: Self.fallbackFileName(for: typeIdentifier),
            completion: completion
        )
    }

    private func importFileRepresentation(
        from provider: NSItemProvider,
        typeIdentifiers: ArraySlice<String>,
        requestedName: String,
        completion: @escaping (ShelfImportResult) -> Void
    ) {
        guard let typeIdentifier = typeIdentifiers.first else {
            completion(.failure(ShelfImportError()))
            return
        }

        provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
            guard let url else {
                importFileRepresentation(
                    from: provider,
                    typeIdentifiers: typeIdentifiers.dropFirst(),
                    requestedName: requestedName,
                    completion: completion
                )
                return
            }

            do {
                let destinationURL = try inbox.copyItem(at: url, named: requestedName)
                completion(.file(url: destinationURL, isManaged: true))
            } catch {
                importFileRepresentation(
                    from: provider,
                    typeIdentifiers: typeIdentifiers.dropFirst(),
                    requestedName: requestedName,
                    completion: completion
                )
            }
        }
    }

    private static func fileTypeIdentifiers(from provider: NSItemProvider) -> ArraySlice<String> {
        provider.registeredTypeIdentifiers.filter { typeIdentifier in
            typeIdentifier != ShelfDragPayload.typeIdentifier
                && typeIdentifier != UTType.fileURL.identifier
                && typeIdentifier != UTType.url.identifier
        }[...]
    }

    private static func documentFileExtension(for typeIdentifier: String) -> String {
        switch typeIdentifier {
        case "public.html":
            "html"
        case UTType.utf8PlainText.identifier, UTType.plainText.identifier, UTType.text.identifier:
            "txt"
        default:
            "md"
        }
    }

    private static func fallbackFileName(for typeIdentifier: String) -> String {
        let baseName = "File-\(Date().compactTimestamp())"
        guard let fileExtension = UTType(typeIdentifier)?.preferredFilenameExtension,
              !fileExtension.isEmpty else {
            return baseName
        }
        return "\(baseName).\(fileExtension)"
    }

    private static func imageFileExtension(for typeIdentifier: String) -> String {
        switch typeIdentifier {
        case UTType.tiff.identifier:
            "tiff"
        case "public.jpeg":
            "jpg"
        case "com.compuserve.gif":
            "gif"
        case "public.heic":
            "heic"
        case "public.heif":
            "heif"
        case "public.svg-image", "com.adobe.svg":
            "svg"
        case "org.webmproject.webp":
            "webp"
        default:
            "png"
        }
    }

    private static func url(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let url = item as? NSURL {
            return url as URL
        }
        if let data = item as? Data,
           let rawValue = String(data: data, encoding: .utf8) {
            return URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let rawValue = item as? String {
            return URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func text(from item: NSSecureCoding?) -> String? {
        if let text = item as? String {
            return text
        }
        if let text = item as? NSString {
            return text as String
        }
        if let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
}
