import AppKit
import Combine
import QuickLookThumbnailing
import UniformTypeIdentifiers

@MainActor
final class ShelfThumbnailLoader: ObservableObject {
    @Published private(set) var image: NSImage?

    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 96
        cache.totalCostLimit = 8 * 1_024 * 1_024
        return cache
    }()

    private var request: QLThumbnailGenerator.Request?
    private var generation = UUID()

    func load(item: ShelfItem, size: CGFloat, scale: CGFloat) {
        cancel()
        image = nativeIcon(for: item)

        guard let url = item.url, url.isFileURL, item.kind != .folder,
              let values = try? url.resourceValues(forKeys: [
                  .contentTypeKey, .contentModificationDateKey, .fileSizeKey, .isRegularFileKey
              ]),
              values.isRegularFile == true,
              let contentType = values.contentType,
              contentType.conforms(to: .image) || contentType.conforms(to: .pdf) else {
            return
        }

        let key = [
            url.standardizedFileURL.absoluteString,
            String(values.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0),
            String(values.fileSize ?? 0),
            String(Double(size)),
            String(Double(scale))
        ].joined(separator: "\u{0}")
        if let cached = Self.cache.object(forKey: key as NSString) {
            image = cached
            return
        }

        let token = generation
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: size, height: size),
            scale: scale,
            representationTypes: .thumbnail
        )
        request.iconMode = true
        self.request = request

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let representation else { return }
            let thumbnail = representation.nsImage
            let cost = representation.cgImage.bytesPerRow * representation.cgImage.height
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                Self.cache.setObject(thumbnail, forKey: key as NSString, cost: cost)
                self.image = thumbnail
                self.request = nil
            }
        }
    }

    func cancel() {
        generation = UUID()
        if let request {
            QLThumbnailGenerator.shared.cancel(request)
            self.request = nil
        }
    }

    private func nativeIcon(for item: ShelfItem) -> NSImage {
        if let url = item.url, url.isFileURL {
            return NSWorkspace.shared.icon(forFile: url.path)
        }

        let type: UTType
        switch item.kind {
        case .file: type = .data
        case .folder: type = .folder
        case .link: type = .url
        case .text: type = .plainText
        case .image: type = .image
        }
        return NSWorkspace.shared.icon(for: type)
    }
}
