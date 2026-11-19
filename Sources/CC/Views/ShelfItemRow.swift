import SwiftUI

struct ShelfItemRow: View {
    let item: ShelfItem
    let onOpen: () -> Void
    let onReveal: () -> Void
    let onCopy: () -> Void
    let onRemove: () -> Void
    var surface: ShelfSurface = .regular
    var showsIcon = false
    var selection: Binding<Bool>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var appearance: ShelfItemAppearance {
        ShelfItemAppearance(item: item)
    }

    var body: some View {
        Group {
            if let selection {
                Toggle(isOn: selection) {
                    if showsIcon {
                        iconLabel.overlay(alignment: .topLeading) { selectionMark(selection.wrappedValue) }
                    } else {
                        HStack(spacing: 10) {
                            selectionMark(selection.wrappedValue)
                            itemLabel
                        }
                        .padding(.horizontal, 10)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                    }
                }
                .toggleStyle(.button)
                .buttonStyle(.plain)
                .accessibilityLabel(appearance.title)
            } else if showsIcon {
                openable(iconLabel)
                    .contextMenu { itemActions }
                    .accessibilityActions { itemActions }
                    .onDrag { item.dragProvider() }
                    .overlay(alignment: .topTrailing) { detailsMenu }
            } else {
                normalRow
            }
        }
        .foregroundStyle(surface.foreground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                isHovered = hovering
            }
        }
        .padding(.vertical, 2)
    }

    private var rowBackground: Color {
        if selection?.wrappedValue == true { return Color.accentColor.opacity(isHovered ? 0.24 : 0.16) }
        return isHovered ? surface.itemBackground : .clear
    }

    private var preview: some View {
        let lifted = isHovered && !reduceMotion
        return ShelfItemPreview(item: item, size: showsIcon ? 48 : 34)
            .scaleEffect(lifted ? 1.12 : 1)
            .offset(y: lifted ? -2 : 0)
    }

    private var itemLabel: some View {
        HStack(spacing: 10) {
            preview
            VStack(alignment: .leading, spacing: 3) {
                Text(appearance.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .truncationMode(item.kind == .text ? .tail : .middle)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = appearance.visibleSubtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(surface.foreground.opacity(0.72))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func selectionMark(_ selected: Bool) -> some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(selected ? Color.accentColor : surface.secondary)
            .accessibilityHidden(true)
    }

    private var iconLabel: some View {
        VStack(spacing: 4) {
            preview
            Text(appearance.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .truncationMode(item.kind == .text ? .tail : .middle)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private func openable(_ label: some View) -> some View {
        label
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: onOpen)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(appearance.title)
            .accessibilityValue(appearance.subtitle)
            .accessibilityHint(item.kind == .text ? "Copies this text" : "Opens this item")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onOpen() }
            .help(appearance.help)
    }

    private var normalRow: some View {
        HStack(spacing: 10) {
            openable(itemLabel)
                .onDrag { item.dragProvider() }
            detailsMenu
        }
        .contentShape(Rectangle())
        .padding(.leading, 10)
    }

    private var detailsMenu: some View {
        Menu {
            itemActions
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isHovered ? surface.foreground : surface.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help("Item Details")
        .accessibilityLabel("Details for \(appearance.title)")
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
