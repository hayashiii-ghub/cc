import Foundation
import Testing
@testable import CC

struct ShelfScreenPolicyTests {
    private let notebook = ShelfScreenDescriptor(
        id: 1,
        frame: CGRect(x: 0, y: 0, width: 1_512, height: 982)
    )
    private let external = ShelfScreenDescriptor(
        id: 2,
        frame: CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080)
    )

    @Test func routesThePointerOnTheNotebookToItsDisplay() {
        let route = ShelfScreenPolicy.displayID(screens: [notebook, external], location: CGPoint(x: 700, y: 500))
        #expect(route == notebook.id)
    }

    @Test func routesTheShelfToTheDisplayUnderThePointer() {
        let screens = [notebook, external]
        let notebookRoute = ShelfScreenPolicy.displayID(screens: screens, location: CGPoint(x: 700, y: 500))
        let externalRoute = ShelfScreenPolicy.displayID(screens: screens, location: CGPoint(x: -900, y: 500))

        #expect(notebookRoute == notebook.id)
        #expect(externalRoute == external.id)
    }

    @Test func routesAStatusItemClickToItsOwnDisplay() {
        let route = ShelfScreenPolicy.displayID(
            screens: [notebook, external],
            location: CGPoint(x: 700, y: 500),
            preferredScreenID: external.id
        )
        #expect(route == external.id)
    }

    @Test func keepsTheShelfAvailableOnAnExternalDisplay() {
        let route = ShelfScreenPolicy.displayID(screens: [external], location: CGPoint(x: -900, y: 500))
        #expect(route == external.id)
    }

    @Test func handlesDisplayAttachmentAndRemoval() {
        let location = CGPoint(x: -900, y: 500)
        let afterRemoval = ShelfScreenPolicy.displayID(
            screens: [notebook], location: location, preferredScreenID: external.id
        )
        let afterAttachment = ShelfScreenPolicy.displayID(screens: [notebook, external], location: location)

        #expect(afterRemoval == notebook.id)
        #expect(afterAttachment == external.id)
    }

    @Test func returnsNoTargetWhileTheScreenListIsEmpty() {
        #expect(ShelfScreenPolicy.displayID(screens: [], location: .zero) == nil)
    }
}
