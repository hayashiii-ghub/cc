import SwiftUI

struct ShelfItemRow: View {
    let item: ShelfItem
    let onOpen: () -> Void
    let onReveal: () -> Void
    let onCopy: () -> Void
    let onRemove: () -> Void
    var surface: ShelfSurface = .regular
    @State private var isHovered = false

    private var appearance: ShelfItemAppearance {
        ShelfItemAppearance(item: item)
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                ShelfItemPreview(item: item, size: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(appearance.title)
                        .font(.system(size: 13, weight: .regular))
                        .lineLimit(2)
                        .truncationMode(item.kind == .text ? .tail : .middle)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(appearance.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(surface.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: onOpen)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(appearance.title)
            .accessibilityValue(appearance.subtitle)
            .accessibilityHint(item.kind == .text ? "Copies this text" : "Opens this item")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onOpen() }
            .help(appearance.help)

            Menu {
                itemActions
            } label: {
                Text("Details")
                    .font(.system(size: 12, weight: .regular))
                    .padding(.horizontal, 4)
                    .frame(height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Item Details")
            .accessibilityLabel("Details for \(appearance.title)")
        }
        .contentShape(Rectangle())
        .foregroundStyle(surface.foreground)
        .padding(10)
        .background(
            isHovered ? surface.itemBackground : .clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .onHover { isHovered = $0 }
    }

    private var itemActions: some View {
        ShelfItemActions(
            item: item,
            onOpen: onOpen,
            onCopy: onCopy,
            onReveal: onReveal,
            onRemove: onRemove
        )
    }
}
