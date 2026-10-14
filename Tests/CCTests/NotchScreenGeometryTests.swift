import AppKit
import Testing
@testable import CC

struct NotchScreenGeometryTests {
    @Test func resolvesTheGapBetweenAuxiliaryTopAreas() throws {
        let geometry = try #require(nativeGeometry())

        #expect(geometry.notchFrame == NSRect(x: 663.5, y: 950, width: 185, height: 32))
        #expect(geometry.compactFrame == NSRect(x: 625.5, y: 950, width: 261, height: 32))
        #expect(geometry.dropFrame == NSRect(x: 625.5, y: 902, width: 261, height: 80))
        #expect(geometry.expandedFrame(itemCount: 0) == NSRect(x: 576, y: 770, width: 360, height: 212))
    }

    @Test func expandedFramesUseTheSharedShelfSizeAndKeepTheNotchAnchor() throws {
        let geometry = try #require(nativeGeometry())
        let twoItems = geometry.expandedFrame(itemCount: 2)
        let sevenItems = geometry.expandedFrame(itemCount: 7)

        #expect(twoItems == NSRect(x: 576, y: 704, width: 360, height: 278))
        #expect(sevenItems == NSRect(x: 576, y: 530, width: 360, height: 452))
        for count in [0, 1, 2, 4, 7, 100] {
            let frame = geometry.expandedFrame(itemCount: count)
            #expect(frame.width == ShelfLayout.size(itemCount: count).width)
            #expect(frame.height == geometry.topInset + ShelfLayout.size(itemCount: count).height)
            #expect(frame.midX == geometry.notchFrame.midX)
            #expect(frame.maxY == geometry.notchFrame.maxY)
        }
    }

    @Test func usesThePhysicalNotchOnATranslatedScreen() throws {
        let geometry = try #require(nativeGeometry(origin: NSPoint(x: -1512, y: 982)))

        #expect(geometry.notchFrame == NSRect(x: -848.5, y: 1932, width: 185, height: 32))
        #expect(geometry.expandedFrame(itemCount: 7) == NSRect(x: -936, y: 1512, width: 360, height: 452))
        for frame in [geometry.compactFrame, geometry.dropFrame, geometry.expandedFrame(itemCount: 7)] {
            #expect(frame.midX == geometry.notchFrame.midX)
            #expect(frame.maxY == geometry.screenFrame.maxY)
            #expect(geometry.screenFrame.contains(frame))
        }
    }

    @Test func rejectsScreensWithoutANotchSafeArea() {
        let geometry = NotchScreenGeometry.resolve(
            screenFrame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: NSRect(x: 0, y: 0, width: 1920, height: 1055),
            safeTopInset: 0,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil
        )

        #expect(geometry == nil)
    }

    @Test func rejectsInvalidAuxiliaryAreaOrdering() {
        let geometry = NotchScreenGeometry.resolve(
            screenFrame: NSRect(x: 0, y: 0, width: 1000, height: 700),
            visibleFrame: NSRect(x: 0, y: 0, width: 1000, height: 668),
            safeTopInset: 32,
            auxiliaryTopLeftArea: NSRect(x: 0, y: 668, width: 550, height: 32),
            auxiliaryTopRightArea: NSRect(x: 500, y: 668, width: 500, height: 32)
        )

        #expect(geometry == nil)
    }

    private func nativeGeometry(origin: NSPoint = .zero) -> NotchScreenGeometry? {
        NotchScreenGeometry.resolve(
            screenFrame: NSRect(x: origin.x, y: origin.y, width: 1512, height: 982),
            visibleFrame: NSRect(x: origin.x, y: origin.y, width: 1512, height: 949),
            safeTopInset: 32,
            auxiliaryTopLeftArea: NSRect(x: origin.x, y: origin.y + 950, width: 663.5, height: 32),
            auxiliaryTopRightArea: NSRect(x: origin.x + 848.5, y: origin.y + 950, width: 663.5, height: 32)
        )
    }
}
