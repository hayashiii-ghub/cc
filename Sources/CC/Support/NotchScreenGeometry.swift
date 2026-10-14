import AppKit

struct NotchScreenGeometry: Equatable {
    static let idleSideTabWidth: CGFloat = 38
    static let dropMinimumWidth: CGFloat = 230
    static let dropExtraHeight: CGFloat = 48

    let screenFrame: NSRect
    let visibleFrame: NSRect
    let notchFrame: NSRect

    var topInset: CGFloat {
        notchFrame.height
    }

    static func resolve(
        screenFrame: NSRect,
        visibleFrame: NSRect,
        safeTopInset: CGFloat,
        auxiliaryTopLeftArea: NSRect?,
        auxiliaryTopRightArea: NSRect?
    ) -> NotchScreenGeometry? {
        guard safeTopInset > 0,
              let leftArea = auxiliaryTopLeftArea,
              let rightArea = auxiliaryTopRightArea else {
            return nil
        }

        let notchMinX = max(screenFrame.minX, leftArea.maxX)
        let notchMaxX = min(screenFrame.maxX, rightArea.minX)
        guard notchMaxX > notchMinX else { return nil }

        return NotchScreenGeometry(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            notchFrame: NSRect(
                x: notchMinX,
                y: screenFrame.maxY - safeTopInset,
                width: notchMaxX - notchMinX,
                height: safeTopInset
            )
        )
    }

    var compactFrame: NSRect {
        topCenteredFrame(
            size: NSSize(
                width: notchFrame.width + Self.idleSideTabWidth * 2,
                height: topInset
            )
        )
    }

    var dropFrame: NSRect {
        topCenteredFrame(
            size: NSSize(
                width: max(
                    Self.dropMinimumWidth,
                    notchFrame.width + Self.idleSideTabWidth * 2
                ),
                height: topInset + Self.dropExtraHeight
            )
        )
    }

    func expandedFrame(itemCount: Int) -> NSRect {
        let content = ShelfLayout.size(itemCount: itemCount)
        return topCenteredFrame(size: NSSize(width: content.width, height: topInset + content.height))
    }

    private func topCenteredFrame(size: NSSize, edgeInset: CGFloat = 8) -> NSRect {
        let availableWidth = max(0, screenFrame.width - edgeInset * 2)
        let width = min(size.width, availableWidth)
        let minimumX = screenFrame.minX + edgeInset
        let maximumX = screenFrame.maxX - width - edgeInset
        let centeredX = notchFrame.midX - width / 2
        return NSRect(
            x: min(max(centeredX, minimumX), maximumX),
            y: notchFrame.maxY - size.height,
            width: width,
            height: size.height
        )
    }
}

extension NSScreen {
    var ccNotchGeometry: NotchScreenGeometry? {
        NotchScreenGeometry.resolve(
            screenFrame: frame,
            visibleFrame: visibleFrame,
            safeTopInset: safeAreaInsets.top,
            auxiliaryTopLeftArea: auxiliaryTopLeftArea,
            auxiliaryTopRightArea: auxiliaryTopRightArea
        )
    }
}
