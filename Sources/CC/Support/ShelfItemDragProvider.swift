import AppKit
import Foundation

enum ShelfDragPayload {
    static let typeIdentifier = "work.hayashigoto.cc.shelf-item"
    static let pasteboardType = NSPasteboard.PasteboardType(typeIdentifier)
}

extension ShelfItem {
    func dragProvider() -> NSItemProvider {
        let provider: NSItemProvider

        if let url {
            provider = NSItemProvider(object: url as NSURL)
            provider.suggestedName = preferredFileName(fallback: url.lastPathComponent)

            if kind == .link {
                provider.registerObject(url.absoluteString as NSString, visibility: .all)
            }
        } else if let text {
            provider = NSItemProvider(object: text as NSString)
            provider.suggestedName = title.sanitizedFileName(defaultName: "Text")
        } else {
            provider = NSItemProvider(object: title as NSString)
        }

        provider.registerDataRepresentation(
            forTypeIdentifier: ShelfDragPayload.typeIdentifier,
            visibility: .all
        ) { completion in
            completion(Data(id.uuidString.utf8), nil)
            return nil
        }
        return provider
    }
}

extension Collection where Element == ShelfItem {
    var batchDragFileURLs: [URL] {
        compactMap { item in
            guard item.kind == .file || item.kind == .folder || item.kind == .image,
                  let url = item.url,
                  url.isFileURL else {
                return nil
            }
            return url
        }
    }
}
