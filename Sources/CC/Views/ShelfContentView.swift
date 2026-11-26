import AppKit
import SwiftUI

struct ShelfContentView: View {
    @ObservedObject var store: ShelfStore
    let onShowSettings: () -> Void

    @State private var isSelecting = false
    @State private var selectedIDs = Set<UUID>()

    var body: some View {
        VStack(spacing: 0) {
            ShelfHeader(
                count: store.items.count,
                selectedCount: isSelecting ? selectedIDs.count : nil,
                showsIcons: store.showsIcons,
                toggleLayout: { store.showsIcons.toggle() },
                toggleSelection: {
                    selectedIDs.removeAll()
                    isSelecting.toggle()
                },
                hasUnreadItems: !store.unreadItemIDs.isEmpty,
                canClearAll: !store.items.isEmpty && !store.isExporting && !store.isImporting && (!isSelecting || !selectedIDs.isEmpty),
                onClearAll: { store.requestRemoval(selectedIDs: isSelecting ? selectedIDs : nil) },
                onShowSettings: onShowSettings
            )
            .disabled(store.pendingRemoval != nil)

            Divider()

            Group {
                if let message = store.storageError {
                    ShelfStorageErrorView(message: message, onRetry: store.refresh)
                } else if store.items.isEmpty {
                    ShelfEmptyView()
                } else {
                    itemList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .disabled(store.pendingRemoval != nil)

            Divider()

            if let request = store.pendingRemoval {
                removalBar(request)
            } else {
                ActionBar(
                    store: store,
                    selectedItems: isSelecting ? store.items.filter { selectedIDs.contains($0.id) } : nil
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: store.items.map(\.id)) { _, ids in
            selectedIDs.formIntersection(ids)
            if ids.isEmpty { isSelecting = false }
        }
    }

    private func removalBar(_ request: ShelfRemovalRequest) -> some View {
        let count = request.ids.count
        let title = request.clearsShelf ? "Clear all \(count)" : "Remove \(count)"
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(title) \(count == 1 ? "item" : "items")?")
                    .font(.headline)
                Text("Original files stay in place.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            GlassEffectContainer(spacing: 0) {
                HStack(spacing: 8) {
                    Button(action: store.cancelRemoval) {
                        Text("Cancel").glassControlLabel(width: 68)
                    }
                    .keyboardShortcut(.defaultAction)
                    Button(role: .destructive, action: store.confirmRemoval) {
                        Text(request.clearsShelf ? "Clear All" : "Remove")
                            .foregroundStyle(.white)
                            .glassControlLabel(width: 74, tint: Color(.sRGB, red: 0.60, green: 0.06, blue: 0.10))
                    }
                    .disabled(store.isImporting || store.isExporting || store.storageError != nil)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: ShelfLayout.footerHeight)
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
                    let removesSelection = isSelecting && selectedIDs.count > 1 && selectedIDs.contains(item.id)
                    ShelfItemRow(
                        item: item,
                        onOpen: { store.open(item) },
                        onReveal: { store.reveal(item) },
                        onCopy: { store.copyToPasteboard(item) },
                        onRemove: {
                            if removesSelection {
                                store.requestRemoval(selectedIDs: selectedIDs)
                            } else {
                                store.removeItem(item.id)
                            }
                        },
                        removesSelection: removesSelection,
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
    let selectedCount: Int?
    let showsIcons: Bool
    let toggleLayout: () -> Void
    let toggleSelection: () -> Void
    let hasUnreadItems: Bool
    let canClearAll: Bool
    let onClearAll: () -> Void
    let onShowSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                titleLabel
                countLabel
            }
            Spacer(minLength: 4)

            GlassIconButton(showsIcons ? "Show as list" : "Show as icons",
                            systemImage: showsIcons ? "list.bullet" : "square.grid.2x2",
                            action: toggleLayout)
            GlassIconButton(selectedCount == nil ? "Select items" : "Finish selection",
                            systemImage: selectedCount == nil ? "checklist" : "checkmark",
                            action: toggleSelection)
                .disabled(count == 0)
                .accessibilityValue(selectedCount == nil ? "Off" : "On")
            GlassIconButton(selectedCount == nil ? "Clear all shelf items…" : "Remove selected items…", systemImage: "trash", action: onClearAll)
                .disabled(!canClearAll)
            GlassIconButton("Settings", systemImage: "gearshape", action: onShowSettings)
        }
        .font(.system(size: 20, weight: .bold, design: .rounded))
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(height: ShelfLayout.headerHeight)
    }

    private var countLabel: some View {
        Text(verbatim: String(selectedCount ?? count))
            .foregroundStyle(Color.primary.opacity(0.82))
            .help(selectedCount.map { "\($0) of \(count) selected" } ?? "\(count) items")
            .lineLimit(1)
            .accessibilityLabel(selectedCount.map { "\($0) of \(count) selected" } ?? "\(count) items in cc:")
    }

    private var titleLabel: some View {
        HStack(spacing: 6) {
            Text("cc:")
                .foregroundStyle(Color.primary)
            if hasUnreadItems {
                Circle().fill(.blue).frame(width: 5, height: 5)
                    .accessibilityLabel("New items")
            }
        }
        .allowsHitTesting(false)
    }
}
