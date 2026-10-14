import SwiftUI

@MainActor
struct ShelfItemPreview: View {
    let item: ShelfItem
    var size: CGFloat = 40

    @Environment(\.displayScale) private var displayScale
    @StateObject private var loader = ShelfThumbnailLoader()

    var body: some View {
        Group {
            if item.kind == .text || item.kind == .link {
                Image(systemName: item.kind.systemImage)
                    .font(.system(size: size * 0.6, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.secondary)
            } else {
                nativePreview
                    .task(id: identity) {
                        loader.load(item: item, size: size, scale: displayScale)
                    }
                    .onDisappear {
                        loader.cancel()
                    }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var nativePreview: some View {
        Group {
            if let image = loader.image {
                Image(nsImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: item.kind.systemImage)
                    .font(.system(size: size * 0.7))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var identity: PreviewIdentity {
        PreviewIdentity(
            id: item.id,
            url: item.url,
            systemImage: item.kind.systemImage,
            size: size,
            scale: displayScale
        )
    }
}

private struct PreviewIdentity: Equatable {
    let id: UUID
    let url: URL?
    let systemImage: String
    let size: CGFloat
    let scale: CGFloat
}
