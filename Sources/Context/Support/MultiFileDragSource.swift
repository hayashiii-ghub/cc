import AppKit
import SwiftUI

final class ShelfFileDragWriter: NSObject, NSPasteboardWriting {
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [.fileURL, ShelfDragPayload.pasteboardType]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        switch type {
        case .fileURL:
            fileURL.absoluteString
        case ShelfDragPayload.pasteboardType:
            fileURL.path
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

struct MultiFileDragSource: NSViewRepresentable {
    let fileURLs: [URL]
    var tint: NSColor = .labelColor

    func makeNSView(context: NSViewRepresentableContext<Self>) -> NSView {
        MultiFileDragSourceView(fileURLs: fileURLs, tint: tint)
    }

    func updateNSView(_ nsView: NSView, context: NSViewRepresentableContext<Self>) {
        guard let dragSourceView = nsView as? MultiFileDragSourceView else { return }
        dragSourceView.fileURLs = fileURLs
        dragSourceView.contentTintColor = tint
    }
}

private final class MultiFileDragSourceView: NSImageView, NSDraggingSource {
    var fileURLs: [URL] {
        didSet {
            updateState()
        }
    }

    private var mouseDownEvent: NSEvent?
    private var isDraggingFiles = false

    init(fileURLs: [URL], tint: NSColor) {
        self.fileURLs = fileURLs
        super.init(frame: .zero)

        let symbol = NSImage(
            systemSymbolName: "square.stack",
            accessibilityDescription: "Drag All Files"
        )
        image = symbol?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        )
        imageScaling = .scaleProportionallyDown
        imageAlignment = .alignLeft
        contentTintColor = tint
        updateState()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 24, height: 24)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        guard fileURLs.count > 1 else { return }
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard fileURLs.count > 1,
              !isDraggingFiles,
              let mouseDownEvent else {
            return
        }

        isDraggingFiles = true
        let location = convert(mouseDownEvent.locationInWindow, from: nil)
        let draggingItems = fileURLs.enumerated().map { index, fileURL in
            let item = NSDraggingItem(pasteboardWriter: ShelfFileDragWriter(fileURL: fileURL))
            let offset = CGFloat(min(index, 3)) * 2
            let frame = NSRect(
                x: location.x - 16 + offset,
                y: location.y - 16 - offset,
                width: 32,
                height: 32
            )
            item.setDraggingFrame(frame, contents: NSWorkspace.shared.icon(forFile: fileURL.path))
            return item
        }

        let session = beginDraggingSession(with: draggingItems, event: mouseDownEvent, source: self)
        session.draggingFormation = .stack
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        isDraggingFiles = false
        mouseDownEvent = nil
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: fileURLs.count > 1 ? .openHand : .arrow)
    }

    private func updateState() {
        isEnabled = fileURLs.count > 1
        alphaValue = isEnabled ? 1 : 0.35
        toolTip = fileURLs.count > 1 ? "Drag All \(fileURLs.count) Files" : "Add at Least 2 Files"
        window?.invalidateCursorRects(for: self)
    }
}
