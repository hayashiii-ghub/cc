import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import CC

@MainActor
struct ShortcutPreferencesTests {
    @Test func keepsTheExistingDefaultKeysAndUsesCarbonModifiers() throws {
        #expect(ShortcutConfiguration.defaults.addFinderSelection == ShortcutBinding(
            keyCode: UInt32(kVK_Tab), modifiers: UInt32(optionKey)
        ))
        #expect(ShortcutConfiguration.defaults.toggleShelf == ShortcutBinding(
            keyCode: UInt32(kVK_Tab), modifiers: UInt32(optionKey | shiftKey)
        ))
        #expect(ShortcutConfiguration.defaults.addFinderSelection.displayString == "⌥ Tab")
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command, .option, .shift, .capsLock],
            timestamp: 0, windowNumber: 0, context: nil, characters: "K",
            charactersIgnoringModifiers: "k", isARepeat: false, keyCode: UInt16(kVK_ANSI_K)
        ))
        let binding = ShortcutBinding(event: event)
        #expect(binding.keyCode == UInt32(kVK_ANSI_K))
        #expect(binding.modifiers == UInt32(cmdKey | optionKey | shiftKey))
    }

    @Test func rejectsUnmodifiedTypingModifierKeysAndDuplicateActions() {
        #expect(ShortcutBinding(keyCode: UInt32(kVK_ANSI_A), modifiers: 0).validationMessage != nil)
        #expect(ShortcutBinding(keyCode: UInt32(kVK_Tab), modifiers: UInt32(shiftKey)).validationMessage != nil)
        #expect(ShortcutBinding(keyCode: UInt32(kVK_Command), modifiers: UInt32(cmdKey)).validationMessage != nil)
        #expect(ShortcutBinding(keyCode: 999, modifiers: UInt32(optionKey)).validationMessage != nil)
        #expect(ShortcutBinding(keyCode: UInt32(kVK_F1), modifiers: 0).validationMessage == nil)
        let duplicate = ShortcutConfiguration.defaults.replacing(
            .toggleShelf, with: ShortcutConfiguration.defaults.addFinderSelection
        )
        #expect(duplicate.validationMessage != nil)
    }

    @Test func savesAcceptedValuesAndLoadsThemAtTheNextLaunch() throws {
        try withFixture { defaults, preferences, registrar, controller in
            controller.start(finderIsFrontmost: false)
            let custom = ShortcutBinding(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | optionKey))
            controller.beginRecording(.toggleShelf)
            #expect(registrar.active.isEmpty)
            #expect(controller.setShortcut(custom, for: .toggleShelf))
            #expect(preferences.values.toggleShelf == custom)
            #expect(preferences.recordingAction == nil)
            #expect(preferences.errorMessage == nil)
            #expect(ShortcutPreferences(defaults: defaults).values.toggleShelf == custom)
            #expect(registrar.active.count == 1)
            #expect(registrar.active.first?.action == .toggleShelf)
            #expect(registrar.active.first?.binding == custom)
        }
    }

    @Test func corruptOrDuplicateSavedValuesFallBackToDefaults() throws {
        try withFixture { defaults, _, _, _ in
            defaults.set(Data("invalid".utf8), forKey: "shelfShortcuts")
            #expect(ShortcutPreferences(defaults: defaults).values == .defaults)
            let duplicate = ShortcutConfiguration.defaults.replacing(
                .toggleShelf, with: ShortcutConfiguration.defaults.addFinderSelection
            )
            defaults.set(try JSONEncoder().encode(duplicate), forKey: "shelfShortcuts")
            #expect(ShortcutPreferences(defaults: defaults).values == .defaults)
        }
    }

    @Test func duplicateAndReservedKeysDoNotChangeSavedValues() throws {
        try withFixture { defaults, preferences, registrar, controller in
            controller.start(finderIsFrontmost: true)
            controller.beginRecording(.toggleShelf)
            #expect(!controller.setShortcut(preferences.values.addFinderSelection, for: .toggleShelf))
            #expect(preferences.values == .defaults)
            #expect(defaults.data(forKey: "shelfShortcuts") == nil)
            #expect(preferences.errorMessage != nil)
            #expect(registrar.active.count == 2)
            let reserved = ShortcutBinding(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey))
            registrar.reserved = [reserved]
            controller.beginRecording(.toggleShelf)
            #expect(!controller.setShortcut(reserved, for: .toggleShelf))
            #expect(preferences.values == .defaults)
            #expect(defaults.data(forKey: "shelfShortcuts") == nil)
            #expect(registrar.active.count == 2)
            #expect(preferences.recordingAction == nil)
        }
    }

    @Test func failedRegistrationRestoresBothPreviousKeysWithoutSaving() throws {
        try withFixture { defaults, preferences, registrar, controller in
            controller.start(finderIsFrontmost: true)
            let custom = ShortcutBinding(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | optionKey))
            registrar.failBinding = custom
            controller.beginRecording(.toggleShelf)
            #expect(!controller.setShortcut(custom, for: .toggleShelf))
            #expect(preferences.values == .defaults)
            #expect(defaults.data(forKey: "shelfShortcuts") == nil)
            #expect(preferences.errorMessage != nil)
            #expect(registrar.active.count == 2)
            #expect(registrar.active.contains { $0.action == .toggleShelf && $0.binding == preferences.values.toggleShelf })
            #expect(registrar.active.contains { $0.action == .addFinderSelection && $0.binding == preferences.values.addFinderSelection })
        }
    }

    @Test func validatesFinderShortcutEvenWhenFinderIsNotFrontmost() throws {
        try withFixture { defaults, preferences, registrar, controller in
            controller.start(finderIsFrontmost: false)
            let custom = ShortcutBinding(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(controlKey | optionKey))
            registrar.failBinding = custom
            controller.beginRecording(.addFinderSelection)
            #expect(!controller.setShortcut(custom, for: .addFinderSelection))
            #expect(preferences.values == .defaults)
            #expect(defaults.data(forKey: "shelfShortcuts") == nil)
            #expect(registrar.active.count == 1)
            #expect(registrar.active.first?.action == .toggleShelf)
        }
    }

    @Test func restoresDefaultsEvenWhenTheCurrentKeysAreSwapped() throws {
        try withFixture { defaults, preferences, registrar, controller in
            preferences.commit(ShortcutConfiguration(
                addFinderSelection: ShortcutConfiguration.defaults.toggleShelf,
                toggleShelf: ShortcutConfiguration.defaults.addFinderSelection
            ))
            controller.start(finderIsFrontmost: true)
            #expect(controller.restoreDefaults())
            #expect(preferences.values == .defaults)
            #expect(ShortcutPreferences(defaults: defaults).values == .defaults)
            #expect(registrar.active.count == 2)
        }
    }

    @Test func recordingCancelsAndFinderAvailabilityStillControlsRegistration() throws {
        try withFixture { _, preferences, registrar, controller in
            controller.start(finderIsFrontmost: false)
            controller.beginRecording(.addFinderSelection)
            controller.updateFinderAvailability(true)
            #expect(registrar.active.isEmpty)
            controller.cancelRecording(.addFinderSelection)
            #expect(preferences.values == .defaults)
            #expect(preferences.recordingAction == nil)
            #expect(registrar.active.count == 2)
            controller.updateFinderAvailability(false)
            #expect(registrar.active.count == 1)
            #expect(registrar.active.first?.action == .toggleShelf)
            controller.stop()
            #expect(registrar.active.isEmpty)
        }
    }

    @Test func staleActionsCannotFireAfterRecordingOrOutsideFinder() throws {
        let suite = "ShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ShortcutPreferences(defaults: defaults)
        let registrar = FakeShortcutRegistrar()
        var added = 0
        var toggled = 0
        let controller = ShortcutController(
            preferences: preferences, registrar: registrar,
            onAddFinderSelection: { added += 1 }, onToggleShelf: { toggled += 1 }
        )
        controller.start(finderIsFrontmost: true)
        let staleToggle = try #require(registrar.active.first { $0.action == .toggleShelf })
        controller.beginRecording(.toggleShelf)
        staleToggle.handler()
        controller.cancelRecording(.toggleShelf)
        staleToggle.handler()
        #expect(toggled == 0)
        let finder = try #require(registrar.active.first { $0.action == .addFinderSelection })
        controller.updateFinderAvailability(false)
        finder.handler()
        #expect(added == 0)
        registrar.active.first { $0.action == .toggleShelf }?.handler()
        #expect(toggled == 1)
        controller.stop()
    }

    private func withFixture(
        _ body: (UserDefaults, ShortcutPreferences, FakeShortcutRegistrar, ShortcutController) throws -> Void
    ) throws {
        let suite = "ShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ShortcutPreferences(defaults: defaults)
        let registrar = FakeShortcutRegistrar()
        let controller = ShortcutController(
            preferences: preferences, registrar: registrar,
            onAddFinderSelection: {}, onToggleShelf: {}
        )
        defer { controller.stop() }
        try body(defaults, preferences, registrar, controller)
    }
}

@MainActor
private final class FakeShortcutRegistrar: ShortcutRegistering {
    var registrations: [FakeShortcutRegistration] = []
    var failBinding: ShortcutBinding?
    var reserved: [ShortcutBinding] = []
    var active: [FakeShortcutRegistration] { registrations.filter { !$0.isInvalidated } }

    func register(
        _ action: ShelfShortcut, binding: ShortcutBinding, handler: @escaping () -> Void
    ) -> (any ShortcutRegistration)? {
        guard binding != failBinding, !active.contains(where: { $0.binding == binding }) else { return nil }
        let registration = FakeShortcutRegistration(action: action, binding: binding, handler: handler)
        registrations.append(registration)
        return registration
    }

    func isReserved(_ binding: ShortcutBinding) -> Bool { reserved.contains(binding) }
}

private final class FakeShortcutRegistration: ShortcutRegistration {
    let action: ShelfShortcut
    let binding: ShortcutBinding
    let handler: () -> Void
    var isInvalidated = false

    init(action: ShelfShortcut, binding: ShortcutBinding, handler: @escaping () -> Void) {
        self.action = action
        self.binding = binding
        self.handler = handler
    }

    func invalidate() { isInvalidated = true }
}
