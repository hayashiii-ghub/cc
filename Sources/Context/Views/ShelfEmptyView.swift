import SwiftUI

struct ShelfEmptyView: View {
    var surface: ShelfSurface = .regular

    var body: some View {
        Text("Drop files, links, or text here.")
            .font(.system(size: 12))
            .multilineTextAlignment(.center)
            .foregroundStyle(surface.secondary)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
