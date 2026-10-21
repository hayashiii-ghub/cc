import Combine
import Foundation

@MainActor
final class ShelfSoundPreferences: ObservableObject {
    private static let storageKey = "cc.playSoundOnAgentReceipt"
    private let defaults: UserDefaults

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.storageKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.storageKey)
    }
}
