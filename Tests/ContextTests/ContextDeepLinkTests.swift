import Foundation
import Testing
@testable import Context

struct ContextDeepLinkTests {
    @Test func routesShelfActionsAndRejectsOtherURLs() {
        let id = UUID()
        #expect(ContextDeepLink(url: URL(string: "context://shelf")!) == .shelf)
        #expect(ContextDeepLink(url: URL(string: "context://clipboard")!) == .clipboard)
        #expect(ContextDeepLink(url: URL(string: "context://settings")!) == .settings)
        #expect(ContextDeepLink(url: URL(string: "context://item/\(id.uuidString)")!) == .item(id))
        for value in [
            "https://shelf", "context://unknown", "context://item/not-an-id",
            "context://shelf?file=/tmp/example", "context://clipboard/extra",
            "context://user@shelf", "context://shelf:123", "context://settings#extra"
        ] {
            #expect(ContextDeepLink(url: URL(string: value)!) == nil)
        }
    }

}
