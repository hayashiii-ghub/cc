import Testing
@testable import CC

@MainActor
struct NotchIslandPresentationTests {
    @Test func acceptedDropAlwaysFinishesCompact() {
        let presentation = NotchIslandPresentationState()
        presentation.phase = .expanded

        presentation.showAcceptedDrop()
        #expect(presentation.phase == .accepted)

        presentation.finishAcceptedDrop()
        #expect(presentation.phase == .compact)
    }
}
