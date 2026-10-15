import SwiftUI

struct ActionBar: View {
    @ObservedObject var store: ShelfStore
    let surface: ShelfSurface
    let onAddFiles: (() -> Void)?
    let onClearAll: () -> Void
    @State private var clipboardText: String?
    @State private var isDragHovered = false

    init(
        store: ShelfStore,
        surface: ShelfSurface = .regular,
        onAddFiles: (() -> Void)? = nil,
        onClearAll: @escaping () -> Void
    ) {
        self.store = store
        self.surface = surface
        self.onAddFiles = onAddFiles
        self.onClearAll = onClearAll
        _clipboardText = State(initialValue: NSPasteboard.general.string(forType: .string))
    }

    var body: some View {
        HStack(spacing: 4) {
            Button {
                if let onAddFiles {
                    onAddFiles()
                } else {
                    _ = store.addItemsFromOpenPanel()
                }
            } label: {
                actionLabel(store.isImporting ? "Adding…" : "Add Files…", isWorking: store.isImporting)
            }
            .accessibilityLabel(store.isImporting ? "Adding Files" : "Add Files…")
            .help(store.isImporting ? "Adding Files…" : "Add Files…")
            .disabled(store.isExporting || store.isImporting)

            Button {
                _ = store.addClipboardText(clipboardText)
            } label: {
                actionLabel("Paste")
            }
            .accessibilityLabel("Add Clipboard Text")
            .help("Add Clipboard Text")
            .disabled(!store.canAddClipboardText(clipboardText) || store.isExporting)

            Spacer(minLength: 4)

            if store.isExporting {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 12, height: 12)
                    .accessibilityLabel("Copying Items")
                    .help("Copying…")
            }

            if !store.items.isEmpty {
                ShelfItemsDragSource(
                    items: store.items,
                    isEnabled: !isBusy,
                    tint: surface.tint.withAlphaComponent(isBusy ? 0.24 : 0.6)
                )
                .padding(.leading, 8)
                .frame(width: 64, height: 28)
                .overlay(alignment: .leading) {
                    Text("Drag")
                        .padding(.leading, 27)
                        .foregroundStyle(surface.secondary)
                        .opacity(isBusy ? 0.4 : 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .background(
                    isDragHovered && !isBusy ? surface.controlBackground : .clear,
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .onHover { isDragHovered = $0 }
                .accessibilityLabel("Drag All Items")
                .help("Drag \(store.items.count) \(store.items.count == 1 ? "Item" : "Items")")
                .disabled(isBusy)

                Button(action: onClearAll) {
                    actionLabel("Clear All…")
                }
                .accessibilityLabel("Clear All…")
                .help("Clear All…")
                .disabled(isBusy)
            }
        }
        .font(.callout)
        .foregroundStyle(surface.foreground)
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .frame(height: ShelfLayout.footerHeight)
        .task {
            while !Task.isCancelled {
                clipboardText = NSPasteboard.general.string(forType: .string)
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private var isBusy: Bool {
        store.isExporting || store.isImporting
    }

    private func actionLabel(_ title: String, isWorking: Bool = false) -> some View {
        HStack(spacing: 6) {
            if isWorking {
                ProgressView().controlSize(.mini)
            }
            Text(title)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .frame(height: 28)
        .contentShape(RoundedRectangle(cornerRadius: 5))
    }
}
