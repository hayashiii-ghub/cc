import AppKit
import CoreGraphics

enum WindowServerPresentation {
    static func isOnScreen(_ window: NSWindow) -> Bool {
        guard window.isVisible, window.windowNumber > 0 else { return false }

        let windowID = CGWindowID(window.windowNumber)
        guard let descriptions = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow, .excludeDesktopElements],
            windowID
        ) as? [[String: Any]],
            let description = descriptions.first(where: { candidate in
                (candidate[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID
            }) else {
            return false
        }

        return (description[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true
    }
}
