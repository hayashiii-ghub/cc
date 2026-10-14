import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: ShelfStore
    let onDismiss: () -> Void
    let onShowMenu: (NSView) -> Void
    @State private var isDropTargeted = false

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    var body: some View {
        ShelfContentView(store: store, onDismiss: onDismiss, onShowMenu: onShowMenu)
            .background(.thickMaterial, in: panelShape)
            .overlay {
                panelShape.strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.primary.opacity(0.08),
                    lineWidth: isDropTargeted ? 1.5 : 0.5
                )
            }
            .clipShape(panelShape)
            .onDrop(of: ShelfStore.acceptedTypeIdentifiers, isTargeted: $isDropTargeted) { providers in
                store.handleDrop(providers: providers)
            }
    }
}
