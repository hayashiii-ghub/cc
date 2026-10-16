import SwiftUI

struct ShelfItemActions: View {
    let item: ShelfItem
    let onOpen: () -> Void
    let onCopy: () -> Void
    let onReveal: () -> Void
    let onRemove: () -> Void

    var body: some View {
        if item.kind != .text {
            Button("Open", action: onOpen)
        }
        Button("Copy", action: onCopy)
        if item.secondaryAction == .reveal {
            Button("Show in Finder", action: onReveal)
        }
        Divider()
        Button("Remove", role: .destructive, action: onRemove)
    }
}
