import AppKit
import SwiftUI

struct ShelfContentView: View {
    @ObservedObject var store: ShelfStore
    var surface: ShelfSurface = .regular
    let onDismiss: () -> Void
    let onShowSettings: () -> Void
    let onClearAll: () -> Void
    var onAddFiles: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            ShelfHeader(
                count: store.items.count,
                surface: surface,
                hasUnreadItems: !store.unreadItemIDs.isEmpty,
                onDismiss: onDismiss,
                onShowSettings: onShowSettings
            )

            Divider()

            Group {
                if let message = store.storageError {
                    ShelfStorageErrorView(message: message, onRetry: store.refresh, surface: surface)
                } else if store.items.isEmpty {
                    ShelfEmptyView(surface: surface)
                } else {
                    itemList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            ActionBar(
                store: store,
                surface: surface,
                onAddFiles: onAddFiles,
                onClearAll: onClearAll
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var itemList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.items.reversed()) { item in
                    ShelfItemRow(
                        item: item,
                        onOpen: { store.open(item) },
                        onReveal: { store.reveal(item) },
                        onCopy: { store.copyToPasteboard(item) },
                        onRemove: { store.remove(item) },
                        surface: surface
                    )
                    .frame(height: ShelfLayout.rowHeight)
                    .onDrag { item.dragProvider() }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, ShelfLayout.listVerticalPadding)
        }
        .accessibilityLabel("All shelf items, newest first")
    }
}

private struct ShelfHeader: View {
    let count: Int
    let surface: ShelfSurface
    let hasUnreadItems: Bool
    let onDismiss: () -> Void
    let onShowSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                titleLabel

                Text(count > 99 ? "99+ items" : "\(count) \(count == 1 ? "item" : "items")")
                    .foregroundStyle(surface.secondary)
                    .monospacedDigit()
                    .accessibilityLabel("\(count) \(count == 1 ? "item" : "items") in cc:")
            }
            .font(.system(size: 12, weight: .medium))

            Spacer(minLength: 12)

            ShelfHeaderButton(
                systemImage: "gearshape",
                title: "Settings…",
                tint: NSColor(surface.foreground),
                action: onShowSettings
            )
            .frame(width: 26, height: 28)

            ShelfHeaderButton(
                systemImage: "xmark",
                title: "Hide Shelf",
                tint: NSColor(surface.foreground),
                action: onDismiss
            )
            .frame(width: 26, height: 28)
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .frame(height: ShelfLayout.headerHeight)
    }

    private var titleLabel: some View {
        HStack(spacing: 6) {
            Text("cc:")
                .foregroundStyle(surface.foreground)
            if hasUnreadItems {
                Circle().fill(.blue).frame(width: 5, height: 5)
                    .accessibilityLabel("New items")
            }
        }
        .allowsHitTesting(false)
    }
}
