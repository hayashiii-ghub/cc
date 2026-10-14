import AppKit

enum ShelfIcon {
    static func templateImage(hasUnreadItems: Bool = false) -> NSImage {
        let image = loadTemplateImage(pointSize: 20)
        guard hasUnreadItems else { return image }

        let badgedImage = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { rect in
            image.draw(in: rect)
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 0.5, y: 16.5, width: 2.5, height: 2.5)).fill()
            return true
        }
        badgedImage.isTemplate = true
        badgedImage.accessibilityDescription = "cc:, new items"
        return badgedImage
    }

    static func vectorTemplateImage() -> NSImage {
        loadTemplateImage(pointSize: 16)
    }

    private static func loadTemplateImage(pointSize: CGFloat) -> NSImage {
        guard
            let url = Bundle.main.url(forResource: "MenuBarTemplate", withExtension: "svg"),
            let image = NSImage(contentsOf: url)
        else {
            let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: true) { rect in
                guard let context = NSGraphicsContext.current?.cgContext else { return false }
                context.addPath(CCMark().path(in: rect).cgPath)
                context.setFillColor(NSColor.black.cgColor)
                context.fillPath()
                return true
            }
            image.isTemplate = true
            image.accessibilityDescription = "cc:"
            return image
        }

        image.isTemplate = true
        image.size = NSSize(width: pointSize, height: pointSize)
        image.accessibilityDescription = "cc:"
        return image
    }
}
