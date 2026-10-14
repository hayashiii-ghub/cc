import AppKit
import Combine
import Foundation

enum ShelfPresentationMode: String, CaseIterable {
    case menuBar
    case notch
}

@MainActor
final class ShelfPresentationPreferences: ObservableObject {
    private static let storageKey = "shelfPresentationMode"
    private let defaults: UserDefaults

    @Published var mode: ShelfPresentationMode {
        didSet { defaults.set(mode.rawValue, forKey: Self.storageKey) }
    }
    @Published var hasNotchedDisplay = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = defaults.string(forKey: Self.storageKey)
            .flatMap(ShelfPresentationMode.init(rawValue:)) ?? .menuBar
    }
}

struct ShelfScreenDescriptor: Equatable {
    let id: UInt32
    let frame: CGRect
    var hasNotch = false
}

struct ShelfPresentationRoute: Equatable {
    let screenID: UInt32
    var mode: ShelfPresentationMode = .menuBar
}

enum ShelfScreenPolicy {
    static func route(
        screens: [ShelfScreenDescriptor],
        location: CGPoint,
        preferredScreenID: UInt32? = nil,
        mode: ShelfPresentationMode = .menuBar
    ) -> ShelfPresentationRoute? {
        let preferredScreen = preferredScreenID.flatMap { id in
            screens.first { $0.id == id }
        }
        guard let screen = preferredScreen
            ?? screens.first(where: { $0.frame.contains(location) })
            ?? screens.first else {
            return nil
        }
        return ShelfPresentationRoute(
            screenID: screen.id,
            mode: mode == .notch && screen.hasNotch ? .notch : .menuBar
        )
    }
}

extension NSScreen {
    var contextShelfDisplayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
