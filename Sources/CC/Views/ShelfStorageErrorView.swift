import SwiftUI

struct ShelfStorageErrorView: View {
    let message: String
    let onRetry: () -> Void
    var surface: ShelfSurface = .island

    var body: some View {
        VStack(spacing: 8) {
            Text("Could Not Read Shelf")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(surface.foreground)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(surface.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Button("Retry", action: onRetry)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(surface.foreground)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(surface.controlBackground, in: RoundedRectangle(cornerRadius: 8))
                .buttonStyle(.plain)
                .accessibilityLabel("Retry Reading Shelf")
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
