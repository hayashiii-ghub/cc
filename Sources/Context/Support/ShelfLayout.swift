import Foundation

enum ShelfLayout {
    static let width: CGFloat = 360
    static let headerHeight: CGFloat = 44
    static let footerHeight: CGFloat = 48
    static let rowHeight: CGFloat = 68
    static let listVerticalPadding: CGFloat = 8
    static let minimumHeight: CGFloat = 180
    static let maximumHeight: CGFloat = 420

    static func size(itemCount: Int) -> NSSize {
        let contentHeight = headerHeight + footerHeight + listVerticalPadding * 2 + 2
            + CGFloat(max(0, itemCount)) * rowHeight
        return NSSize(width: width, height: min(max(contentHeight, minimumHeight), maximumHeight))
    }

    static func resizedFrame(_ frame: NSRect, itemCount: Int) -> NSRect {
        let size = size(itemCount: itemCount)
        return NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height)
    }
}
