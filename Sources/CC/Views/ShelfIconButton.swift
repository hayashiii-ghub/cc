import SwiftUI

extension View {
    func shelfControlLabel(width: CGFloat = 94, tint: Color? = nil) -> some View {
        self
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(width: width, height: 32)
            .contentShape(Capsule())
            .glassEffect(.regular.tint(tint).interactive(), in: Capsule())
    }
}

struct ShelfIconButton: View {
    let title: LocalizedStringKey
    let image: Image
    let action: () -> Void

    init(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) {
        self.init(title, image: Image(systemName: systemImage), action: action)
    }

    init(_ title: LocalizedStringKey, image: Image, action: @escaping () -> Void) {
        self.title = title
        self.image = image
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            image
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .shelfControlLabel(width: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .help(Text(title))
    }
}
