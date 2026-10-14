import AppKit
import Foundation

struct FinderSelectionReader {
    static let finderBundleIdentifier = "com.apple.finder"

    func selectedFileURLs() throws -> [URL] {
        let source = """
        tell application "Finder"
            set selectedItems to selection
            set selectedPaths to {}
            repeat with selectedItem in selectedItems
                set end of selectedPaths to POSIX path of (selectedItem as alias)
            end repeat
            return selectedPaths
        end tell
        """

        guard let script = NSAppleScript(source: source) else {
            throw FinderSelectionError(message: "Could not create the Finder selection script.")
        }

        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String
                ?? "Finder did not provide its selected items."
            throw FinderSelectionError(message: message)
        }

        return Self.fileURLs(from: descriptor)
    }

    static func fileURLs(from descriptor: NSAppleEventDescriptor) -> [URL] {
        guard descriptor.numberOfItems > 0 else { return [] }

        return (1...descriptor.numberOfItems).compactMap { index in
            guard let path = descriptor.atIndex(index)?.stringValue, !path.isEmpty else {
                return nil
            }
            return URL(fileURLWithPath: path)
        }
    }
}

enum FinderShortcutAvailability {
    static func isEnabled(frontmostBundleIdentifier: String?) -> Bool {
        frontmostBundleIdentifier == FinderSelectionReader.finderBundleIdentifier
    }
}

private struct FinderSelectionError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
