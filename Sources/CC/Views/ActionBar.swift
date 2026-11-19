import SwiftUI

struct ActionBar: View {
    @ObservedObject var store: ShelfStore
    let selectedItems: [ShelfItem]?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                _ = store.addItemsFromOpenPanel()
            } label: {
                HStack(spacing: 5) {
                    if store.isImporting {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "plus")
                    }
                    Text(store.isImporting ? "Adding" : "Add Files")
                }
                .shelfControlLabel()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.isImporting ? "Adding Files" : "Add Files")
            .help(store.isImporting ? "Adding Files" : "Add Files")
            .disabled(store.isExporting || store.isImporting)

            Spacer(minLength: 4)

            if store.isExporting {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 12, height: 12)
                    .accessibilityLabel("Copying Items")
                    .help("Copying")
            }

            if !store.items.isEmpty {
                let items = selectedItems ?? store.items
                HStack(spacing: 5.5) {
                    Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                        ForEach(0..<3) { _ in
                            GridRow {
                                Circle().frame(width: 2.5, height: 2.5)
                                Circle().frame(width: 2.5, height: 2.5)
                            }
                        }
                    }
                    .accessibilityHidden(true)
                    Text(selectedItems == nil ? "Drag All" : "Drag (\(items.count))")
                }
                .shelfControlLabel()
                .foregroundStyle(Color.primary)
                .opacity(isBusy || items.isEmpty ? 0.4 : 1)
                .overlay {
                    ShelfItemsDragSource(items: items, isEnabled: !isBusy)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .accessibilityLabel(selectedItems == nil ? "Drag all items" : "Drag selected items")
                .help(items.isEmpty ? "Choose items to drag" : "Drag \(items.count) \(items.count == 1 ? "Item" : "Items")")
                .disabled(isBusy || items.isEmpty)
            }
        }
        .font(.callout)
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 10)
        .frame(height: ShelfLayout.footerHeight)
    }

    private var isBusy: Bool {
        store.isExporting || store.isImporting
    }
}
