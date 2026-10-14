import Foundation
import Testing
@testable import CC

struct ShelfScreenPolicyTests {
    private let notebook = ShelfScreenDescriptor(
        id: 1,
        frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
        hasNotch: true
    )
    private let external = ShelfScreenDescriptor(
        id: 2,
        frame: CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080)
    )

    @Test func routesThePointerOnTheNotebookToItsDisplay() {
        let route = ShelfScreenPolicy.route(screens: [notebook, external], location: CGPoint(x: 700, y: 500))
        #expect(route == ShelfPresentationRoute(screenID: notebook.id))
    }

    @Test func routesTheShelfToTheDisplayUnderThePointer() {
        let screens = [notebook, external]
        let notebookRoute = ShelfScreenPolicy.route(screens: screens, location: CGPoint(x: 700, y: 500))
        let externalRoute = ShelfScreenPolicy.route(screens: screens, location: CGPoint(x: -900, y: 500))

        #expect(notebookRoute == ShelfPresentationRoute(screenID: notebook.id))
        #expect(externalRoute == ShelfPresentationRoute(screenID: external.id))
    }

    @Test func routesAStatusItemClickToItsOwnDisplay() {
        let route = ShelfScreenPolicy.route(
            screens: [notebook, external],
            location: CGPoint(x: 700, y: 500),
            preferredScreenID: external.id
        )
        #expect(route == ShelfPresentationRoute(screenID: external.id))
    }

    @Test func keepsTheShelfAvailableWithoutANotchedDisplay() {
        let route = ShelfScreenPolicy.route(screens: [external], location: CGPoint(x: -900, y: 500))
        #expect(route == ShelfPresentationRoute(screenID: external.id))
    }

    @Test func handlesDisplayAttachmentAndRemovalWithoutASavedMode() {
        let location = CGPoint(x: -900, y: 500)
        let afterRemoval = ShelfScreenPolicy.route(
            screens: [notebook], location: location, preferredScreenID: external.id
        )
        let afterAttachment = ShelfScreenPolicy.route(screens: [notebook, external], location: location)

        #expect(afterRemoval == ShelfPresentationRoute(screenID: notebook.id))
        #expect(afterAttachment == ShelfPresentationRoute(screenID: external.id))
    }

    @Test func returnsNoTargetWhileTheScreenListIsEmpty() {
        #expect(ShelfScreenPolicy.route(screens: [], location: .zero) == nil)
    }

    @Test func notchPreferenceUsesTheNotchOnlyOnSupportedDisplays() {
        let screens = [notebook, external]
        #expect(ShelfScreenPolicy.route(
            screens: screens, location: CGPoint(x: 700, y: 500), mode: .notch
        ) == ShelfPresentationRoute(screenID: notebook.id, mode: .notch))
        #expect(ShelfScreenPolicy.route(
            screens: screens, location: CGPoint(x: -900, y: 500), mode: .notch
        ) == ShelfPresentationRoute(screenID: external.id, mode: .menuBar))
    }

    @Test func aDisconnectedNotchFallsBackToTheMenuBar() {
        #expect(ShelfScreenPolicy.route(
            screens: [external], location: CGPoint(x: 700, y: 500),
            preferredScreenID: notebook.id, mode: .notch
        ) == ShelfPresentationRoute(screenID: external.id, mode: .menuBar))
    }
}
