import Foundation

enum ShelfLayout {
    static let width: CGFloat = 360
    static let headerHeight: CGFloat = 44
    static let footerHeight: CGFloat = 48
    static let iconColumns = 3
    static let iconRowHeight: CGFloat = 96
    static let rowHeight: CGFloat = 56
    static let listVerticalPadding: CGFloat = 8
    static let minimumHeight: CGFloat = 180
    static let maximumHeight: CGFloat = 420

    static func size(itemCount: Int, showsIcons: Bool = false) -> NSSize {
        let count = max(0, itemCount)
        let rows = showsIcons ? ceil(CGFloat(count) / CGFloat(iconColumns)) : CGFloat(count)
        let contentHeight = headerHeight + footerHeight + listVerticalPadding * 2 + 2
            + rows * (showsIcons ? iconRowHeight : rowHeight)
        return NSSize(width: width, height: min(max(contentHeight, minimumHeight), maximumHeight))
    }

    static func resizedFrame(_ frame: NSRect, itemCount: Int, showsIcons: Bool = false) -> NSRect {
        let size = size(itemCount: itemCount, showsIcons: showsIcons)
        return NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height)
    }
}
