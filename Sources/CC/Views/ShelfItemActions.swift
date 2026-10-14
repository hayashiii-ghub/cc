import SwiftUI

struct ShelfItemActions: View {
    let item: ShelfItem
    let onOpen: () -> Void
    let onCopy: () -> Void
    let onReveal: () -> Void
    let onRemove: () -> Void

    var body: some View {
        if item.kind == .text {
            Button("Copy Text", action: onCopy)
        } else {
            Button("Open", action: onOpen)
            Button(item.kind == .link ? "Copy Link" : "Copy", action: onCopy)
        }
        if item.secondaryAction == .reveal {
            Button("Show in Finder", action: onReveal)
        }
        Divider()
        Button("Remove from Shelf", role: .destructive, action: onRemove)
    }
}
