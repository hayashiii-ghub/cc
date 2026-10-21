import CCCore
import Foundation
import Testing
@testable import CC

@MainActor
struct ShelfReceiptSoundTests {
    @Test func startsDisabledAndPersistsOnlyInTheSelectedDefaultsSuite() throws {
        let fixture = try ReceiptSoundFixture()
        defer { fixture.cleanup() }
        let other = try ReceiptSoundFixture()
        defer { other.cleanup() }
        fixture.defaults.set("keep", forKey: "unrelated")

        #expect(!fixture.preferences.isEnabled)
        fixture.preferences.isEnabled = true
        #expect(fixture.defaults.bool(forKey: "cc.playSoundOnAgentReceipt"))
        #expect(ShelfSoundPreferences(defaults: fixture.defaults).isEnabled)
        #expect(!ShelfSoundPreferences(defaults: other.defaults).isEnabled)

        fixture.preferences.isEnabled = false
        #expect(!ShelfSoundPreferences(defaults: fixture.defaults).isEnabled)
        #expect(fixture.defaults.string(forKey: "unrelated") == "keep")
    }

    @Test func existingAndDisabledArrivalsNeverReplayWhenEnabled() throws {
        let fixture = try ReceiptSoundFixture()
        defer { fixture.cleanup() }
        let existing = record(source: "codex")
        let receivedWhileDisabled = record(source: "claude")
        fixture.sound.observe([existing])
        fixture.sound.observe([existing, receivedWhileDisabled])
        fixture.preferences.isEnabled = true
        fixture.state.time += 10

        fixture.sound.observe([existing, receivedWhileDisabled])
        #expect(fixture.state.playCount == 0)

        fixture.sound.observe([existing, receivedWhileDisabled, record(source: "codex")])
        #expect(fixture.state.playCount == 1)
    }

    @Test func batchesCustomAgentArrivalsAndIgnoresHumansRepeatsAndDeletions() throws {
        let fixture = try ReceiptSoundFixture(enabled: true)
        defer { fixture.cleanup() }
        let human = record(source: "human")
        let grokbot = record(source: "grokbot")
        let customAgent = record(source: "調査 Bot")
        fixture.sound.observe([])
        fixture.sound.observe([human])
        #expect(fixture.state.playCount == 0)

        fixture.sound.observe([human, grokbot, customAgent])
        #expect(fixture.state.playCount == 1)
        fixture.state.time += 10
        fixture.sound.observe([customAgent, human, grokbot])
        fixture.sound.observe([human, grokbot])
        fixture.sound.observe([human, grokbot, record(source: "human")])
        fixture.sound.observe([])
        fixture.sound.observe([grokbot, customAgent])
        #expect(fixture.state.playCount == 1)
    }

    @Test func cooldownUsesTheLastSoundAndNeverReplaysSuppressedArrivals() throws {
        let fixture = try ReceiptSoundFixture(enabled: true)
        defer { fixture.cleanup() }
        let first = record(source: "codex")
        let suppressed = record(source: "claude")
        let next = record(source: "grokbot")
        fixture.sound.observe([])
        fixture.sound.observe([first])
        #expect(fixture.state.playCount == 1)

        fixture.state.time = 101.999
        fixture.sound.observe([first, suppressed])
        #expect(fixture.state.playCount == 1)
        fixture.state.time = 102
        fixture.sound.observe([first, suppressed])
        #expect(fixture.state.playCount == 1)
        fixture.sound.observe([first, suppressed, next])
        #expect(fixture.state.playCount == 2)
    }

    @Test func storeSoundsForExternalArrivalsButKeepsOldUnreadItemsAndFailedRefreshesSilent() throws {
        let fixture = try ReceiptSoundFixture(enabled: true)
        defer { fixture.cleanup() }
        let repository = CCRepository(rootURL: fixture.rootURL)
        let old = try repository.addText("Old unread draft", source: "codex")
        let store = ShelfStore(repository: repository, receiptSound: fixture.sound, errorPresenter: { _ in })
        #expect(store.soundPreferences === fixture.preferences)
        #expect(store.unreadItemIDs == [old.id])
        #expect(fixture.state.playCount == 0)

        let external = CCRepository(rootURL: fixture.rootURL)
        let received = try external.addText("New agent result", source: "調査 Bot")
        store.refresh()
        #expect(Set(store.items.map(\.id)) == [old.id, received.id])
        #expect(fixture.state.playCount == 1)

        let databaseURL = fixture.rootURL.appendingPathComponent("records.json")
        let validDatabase = try Data(contentsOf: databaseURL)
        try Data("corrupt records".utf8).write(to: databaseURL)
        fixture.state.time += 10
        store.refresh()
        #expect(store.storageError != nil)
        #expect(fixture.state.playCount == 1)
        try validDatabase.write(to: databaseURL)
        store.refresh()
        #expect(store.storageError == nil)
        #expect(fixture.state.playCount == 1)

        _ = try external.addText("Result after recovery", source: "claude")
        store.refresh()
        store.refresh()
        #expect(fixture.state.playCount == 2)
    }

    @Test func firstSuccessfulStoreReadIsASilentBaselineAfterStartupFailure() throws {
        let fixture = try ReceiptSoundFixture(enabled: true)
        defer { fixture.cleanup() }
        let repository = CCRepository(rootURL: fixture.rootURL)
        let old = try repository.addText("Previously received result", source: "codex")
        let databaseURL = fixture.rootURL.appendingPathComponent("records.json")
        let validDatabase = try Data(contentsOf: databaseURL)
        try Data("corrupt records".utf8).write(to: databaseURL)
        let store = ShelfStore(repository: repository, receiptSound: fixture.sound, errorPresenter: { _ in })
        #expect(store.storageError != nil)
        #expect(fixture.state.playCount == 0)

        try validDatabase.write(to: databaseURL)
        store.refresh()
        #expect(store.storageError == nil)
        #expect(store.unreadItemIDs == [old.id])
        #expect(fixture.state.playCount == 0)

        _ = try repository.addText("New result after startup", source: "grokbot")
        store.refresh()
        #expect(fixture.state.playCount == 1)
    }

    private func record(source: String) -> CCRecord {
        CCRecord(
            id: UUID(), kind: .text, title: "Result", text: "Result", source: source,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }
}

@MainActor
private final class ReceiptSoundFixture {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("CCTests.receiptSound.\(UUID().uuidString)", isDirectory: true)
    let suiteName: String
    let defaults: UserDefaults
    let preferences: ShelfSoundPreferences
    let state: ReceiptSoundState
    let sound: ShelfReceiptSound

    init(enabled: Bool = false) throws {
        suiteName = "CCTests.receiptSound.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        preferences = ShelfSoundPreferences(defaults: defaults)
        if enabled { preferences.isEnabled = true }
        let state = ReceiptSoundState()
        self.state = state
        sound = ShelfReceiptSound(
            preferences: preferences,
            now: { state.time },
            playSound: { state.playCount += 1 }
        )
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: rootURL)
    }
}

@MainActor
private final class ReceiptSoundState {
    var time: TimeInterval = 100
    var playCount = 0
}
