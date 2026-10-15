import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class ShelfItemDragWriter: NSObject, NSPasteboardWriting {
    let item: ShelfItem

    init(item: ShelfItem) {
        self.item = item
    }

    private var fileURL: URL? {
        guard item.kind == .file || item.kind == .folder || item.kind == .image,
              let url = item.url, url.isFileURL else { return nil }
        return url
    }

    private var linkURL: URL? {
        guard item.kind == .link, let url = item.url, !url.isFileURL else { return nil }
        return url
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        let contentTypes: [NSPasteboard.PasteboardType]
        if fileURL != nil {
            contentTypes = [.fileURL]
        } else if linkURL != nil {
            contentTypes = [.URL, .string]
        } else {
            contentTypes = [.string]
        }
        return contentTypes + [ShelfDragPayload.pasteboardType]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        switch type {
        case .fileURL:
            fileURL?.absoluteString
        case .URL:
            linkURL?.absoluteString
        case .string:
            fileURL == nil ? (linkURL?.absoluteString ?? item.text ?? item.title) : nil
        case ShelfDragPayload.pasteboardType:
            item.id.uuidString
        default:
            nil
        }
    }

    func writingOptions(
        forType type: NSPasteboard.PasteboardType,
        pasteboard: NSPasteboard
    ) -> NSPasteboard.WritingOptions {
        []
    }
}

struct ShelfItemsDragSource: NSViewRepresentable {
    let items: [ShelfItem]
    var isEnabled = true
    var tint: NSColor = .labelColor

    func makeNSView(context: NSViewRepresentableContext<Self>) -> NSView {
        ShelfItemsDragSourceView(items: items, isEnabled: isEnabled, tint: tint)
    }

    func updateNSView(_ nsView: NSView, context: NSViewRepresentableContext<Self>) {
        guard let dragSourceView = nsView as? ShelfItemsDragSourceView else { return }
        dragSourceView.items = items
        dragSourceView.allowsDragging = isEnabled
        dragSourceView.contentTintColor = tint
    }
}

private final class ShelfItemsDragSourceView: NSImageView, NSDraggingSource {
    var items: [ShelfItem] {
        didSet { updateState() }
    }
    var allowsDragging: Bool {
        didSet { updateState() }
    }

    private var mouseDownEvent: NSEvent?
    private var isDraggingItems = false

    init(items: [ShelfItem], isEnabled: Bool, tint: NSColor) {
        self.items = items
        allowsDragging = isEnabled
        super.init(frame: .zero)

        let symbol = NSImage(
            systemSymbolName: "square.stack",
            accessibilityDescription: "Drag All Items"
        )
        image = symbol?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        )
        imageScaling = .scaleProportionallyDown
        imageAlignment = .alignLeft
        contentTintColor = tint
        updateState()
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize { NSSize(width: 24, height: 24) }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        mouseDownEvent = event
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled, !isDraggingItems, let mouseDownEvent else { return }

        isDraggingItems = true
        let location = convert(mouseDownEvent.locationInWindow, from: nil)
        let draggingItems = items.enumerated().map { index, shelfItem in
            let item = NSDraggingItem(pasteboardWriter: ShelfItemDragWriter(item: shelfItem))
            let offset = CGFloat(min(index, 3)) * 2
            let frame = NSRect(
                x: location.x - 16 + offset,
                y: location.y - 16 - offset,
                width: 32,
                height: 32
            )
            let icon: NSImage
            if let url = shelfItem.url, url.isFileURL {
                icon = NSWorkspace.shared.icon(forFile: url.path)
            } else {
                icon = NSWorkspace.shared.icon(for: shelfItem.kind == .link ? .url : .plainText)
            }
            item.setDraggingFrame(frame, contents: icon)
            return item
        }

        let session = beginDraggingSession(with: draggingItems, event: mouseDownEvent, source: self)
        session.draggingFormation = .stack
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation { .copy }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        isDraggingItems = false
        mouseDownEvent = nil
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: isEnabled ? .openHand : .arrow)
    }

    private func updateState() {
        isEnabled = allowsDragging && !items.isEmpty
        alphaValue = isEnabled ? 1 : 0.35
        if items.isEmpty {
            toolTip = "Add an Item to Drag"
        } else if !allowsDragging {
            toolTip = "Wait for the Current Operation"
        } else {
            toolTip = "Drag All \(items.count) \(items.count == 1 ? "Item" : "Items")"
        }
        if !isEnabled { mouseDownEvent = nil }
        window?.invalidateCursorRects(for: self)
    }
}
