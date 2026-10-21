import AppKit
import CCCore
import Foundation

@MainActor
final class ShelfReceiptSound {
    let preferences: ShelfSoundPreferences
    private let now: @MainActor () -> TimeInterval
    private let playSound: @MainActor () -> Void
    private var knownItemIDs: Set<UUID>?
    private var lastPlayedAt: TimeInterval?

    init(
        preferences: ShelfSoundPreferences? = nil,
        now: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        playSound: @escaping @MainActor () -> Void = ShelfReceiptSound.playReceiptSound
    ) {
        self.preferences = preferences ?? ShelfSoundPreferences()
        self.now = now
        self.playSound = playSound
    }

    func observe(_ records: [CCRecord]) {
        let currentIDs = Set(records.map(\.id))
        guard let knownIDs = knownItemIDs else {
            knownItemIDs = currentIDs
            return
        }
        knownItemIDs = knownIDs.union(currentIDs)
        guard preferences.isEnabled,
              records.contains(where: { $0.source != "human" && !knownIDs.contains($0.id) }) else {
            return
        }
        let timestamp = now()
        if let lastPlayedAt, timestamp - lastPlayedAt < 2 { return }
        lastPlayedAt = timestamp
        playSound()
    }

    private static func playReceiptSound() {
        NSSound(named: NSSound.Name("Glass"))?.play()
    }
}
