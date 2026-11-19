import AppKit
import SwiftUI

struct ShelfContentView: View {
    @ObservedObject var store: ShelfStore
    var surface: ShelfSurface = .regular
    let onShowSettings: () -> Void
    let onClearAll: () -> Void
    var onAddFiles: (() -> Void)? = nil

    @State private var isSelecting = false
    @State private var selectedIDs = Set<UUID>()

    var body: some View {
        VStack(spacing: 0) {
            ShelfHeader(
                count: store.items.count,
                surface: surface,
                selectedCount: isSelecting ? selectedIDs.count : nil,
                showsIcons: store.showsIcons,
                toggleLayout: { store.showsIcons.toggle() },
                toggleSelection: {
                    selectedIDs.removeAll()
                    isSelecting.toggle()
                },
                hasUnreadItems: !store.unreadItemIDs.isEmpty,
                canClearAll: !store.items.isEmpty && !store.isExporting && !store.isImporting && !isSelecting,
                onClearAll: onClearAll,
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
                selectedItems: isSelecting ? store.items.filter { selectedIDs.contains($0.id) } : nil,
                surface: surface,
                onAddFiles: onAddFiles
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: store.items.map(\.id)) { _, ids in
            selectedIDs.formIntersection(ids)
            if ids.isEmpty { isSelecting = false }
        }
    }

    private func selection(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedIDs.contains(id) },
            set: { checked in
                if checked { selectedIDs.insert(id) }
                else { selectedIDs.remove(id) }
            }
        )
    }

    private var itemList: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6),
                                     count: store.showsIcons ? ShelfLayout.iconColumns : 1), spacing: 0) {
                ForEach(store.items.reversed()) { item in
                    ShelfItemRow(
                        item: item,
                        onOpen: { store.open(item) },
                        onReveal: { store.reveal(item) },
                        onCopy: { store.copyToPasteboard(item) },
                        onRemove: { store.remove(item) },
                        surface: surface,
                        showsIcon: store.showsIcons,
                        selection: isSelecting ? selection(for: item.id) : nil
                    )
                    .frame(height: store.showsIcons ? ShelfLayout.iconRowHeight : ShelfLayout.rowHeight)
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
    let selectedCount: Int?
    let showsIcons: Bool
    let toggleLayout: () -> Void
    let toggleSelection: () -> Void
    private static let selectImage: Image = {
        guard let url = Bundle.main.url(forResource: "SelectItems", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return Image(systemName: "checklist") }
        return Image(nsImage: image).renderingMode(.template)
    }()

    let hasUnreadItems: Bool
    let canClearAll: Bool
    let onClearAll: () -> Void
    let onShowSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                titleLabel
                Text(verbatim: String(selectedCount ?? count))
                    .foregroundStyle(surface.foreground.opacity(0.82))
                    .help(selectedCount.map { "\($0) of \(count) selected" } ?? "\(count) items")
                    .lineLimit(1)
                    .accessibilityLabel(selectedCount.map { "\($0) of \(count) selected" } ?? "\(count) items in cc:")
            }

            Spacer(minLength: 4)

            ShelfIconButton(showsIcons ? "Show as list" : "Show as icons",
                            systemImage: showsIcons ? "list.bullet" : "square.grid.2x2",
                            action: toggleLayout)
            ShelfIconButton(selectedCount == nil ? "Select items" : "Finish selection",
                            image: selectedCount == nil ? Self.selectImage : Image(systemName: "checkmark"),
                            action: toggleSelection)
                .disabled(count == 0)
                .accessibilityValue(selectedCount == nil ? "Off" : "On")
            ShelfIconButton("Clear all shelf items…", systemImage: "trash", action: onClearAll)
                .disabled(!canClearAll)
            ShelfIconButton("Settings", systemImage: "gearshape", action: onShowSettings)
        }
        .font(.system(size: 20, weight: .bold, design: .rounded))
        .padding(.leading, 16)
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
