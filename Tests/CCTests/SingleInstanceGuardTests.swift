import Foundation
import Testing
@testable import CC

struct SingleInstanceGuardTests {
    @Test func onlyOneGuardCanOwnAnApplicationIdentifier() {
        let identifier = "CCTests.\(UUID().uuidString)"
        let first = SingleInstanceGuard(identifier: identifier)
        let second = SingleInstanceGuard(identifier: identifier)

        #expect(first != nil)
        #expect(second == nil)
    }
}
