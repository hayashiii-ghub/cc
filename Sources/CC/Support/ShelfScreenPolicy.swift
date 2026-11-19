import AppKit

struct ShelfScreenDescriptor: Equatable {
    let id: UInt32
    let frame: CGRect
}

enum ShelfScreenPolicy {
    static func displayID(
        screens: [ShelfScreenDescriptor],
        location: CGPoint,
        preferredScreenID: UInt32? = nil
    ) -> UInt32? {
        let preferredScreen = preferredScreenID.flatMap { id in
            screens.first { $0.id == id }
        }
        let screen = preferredScreen ?? screens.first { $0.frame.contains(location) } ?? screens.first
        return screen?.id
    }
}

extension NSScreen {
    var ccShelfDisplayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
