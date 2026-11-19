import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: ShelfStore
    let onShowSettings: () -> Void
    @State private var isDropTargeted = false

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }

    var body: some View {
        ShelfContentView(
            store: store,
            onShowSettings: onShowSettings
        )
            .glassEffect(.regular, in: panelShape)
            .overlay {
                panelShape.strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.primary.opacity(0.08),
                    lineWidth: isDropTargeted ? 1.5 : 0.5
                )
                .allowsHitTesting(false)
            }
            .clipShape(panelShape)
            .onDrop(of: ShelfStore.acceptedTypeIdentifiers, isTargeted: $isDropTargeted) { providers in
                store.pendingRemoval == nil && store.handleDrop(providers: providers)
            }
    }
}
