import Foundation
import Testing
@testable import CC

struct ShelfLayoutTests {
    @Test func emptyAndSingleItemShelvesKeepAUsableDropArea() {
        #expect(ShelfLayout.size(itemCount: 0) == NSSize(width: 360, height: 180))
        #expect(ShelfLayout.size(itemCount: 1).height == 180)
        #expect(ShelfLayout.size(itemCount: -1).height == 180)
        let dropHeight = ShelfLayout.size(itemCount: 0).height
            - ShelfLayout.headerHeight - ShelfLayout.footerHeight - 2
        #expect(dropHeight >= 80)
    }

    @Test func heightGrowsWithRowsAndStopsAtTheScrollLimit() {
        #expect(ShelfLayout.size(itemCount: 2).height == 246)
        #expect(ShelfLayout.size(itemCount: 4).height == 382)
        #expect(ShelfLayout.size(itemCount: 7).height == 420)
        #expect(ShelfLayout.size(itemCount: 100).height == 420)
    }

    @Test func resizingKeepsTheMenuBarAnchorFixed() {
        var frame = NSRect(x: -450, y: 1_000, width: 360, height: 180)
        let top = frame.maxY
        for count in [0, 2, 4, 7, 1] {
            frame = ShelfLayout.resizedFrame(frame, itemCount: count)
            #expect(frame.maxY == top)
            #expect(frame.minX == -450)
            #expect(frame.size == ShelfLayout.size(itemCount: count))
        }
    }
}
