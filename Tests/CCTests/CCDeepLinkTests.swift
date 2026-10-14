import Foundation
import Testing
@testable import CC

struct CCDeepLinkTests {
    @Test func routesShelfActionsAndRejectsOtherURLs() {
        let id = UUID()
        #expect(CCDeepLink(url: URL(string: "cc://shelf")!) == .shelf)
        #expect(CCDeepLink(url: URL(string: "cc://clipboard")!) == .clipboard)
        #expect(CCDeepLink(url: URL(string: "cc://settings")!) == .settings)
        #expect(CCDeepLink(url: URL(string: "cc://item/\(id.uuidString)")!) == .item(id))
        for value in [
            "https://shelf", "cc://unknown", "cc://item/not-an-id",
            "cc://shelf?file=/tmp/example", "cc://clipboard/extra",
            "cc://user@shelf", "cc://shelf:123", "cc://settings#extra"
        ] {
            #expect(CCDeepLink(url: URL(string: value)!) == nil)
        }
    }

}
