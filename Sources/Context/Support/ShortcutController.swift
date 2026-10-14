import Foundation

protocol ShortcutRegistration: AnyObject {
    func invalidate()
}

@MainActor
protocol ShortcutRegistering {
    func register(
        _ action: ShelfShortcut,
        binding: ShortcutBinding,
        handler: @escaping () -> Void
    ) -> (any ShortcutRegistration)?
    func isReserved(_ binding: ShortcutBinding) -> Bool
}

@MainActor
final class ShortcutController {
    let preferences: ShortcutPreferences
    private let registrar: any ShortcutRegistering
    private let onAddFinderSelection: () -> Void
    private let onToggleShelf: () -> Void
    private var registrations: [ShelfShortcut: any ShortcutRegistration] = [:]
    private var isStarted = false
    private var finderIsFrontmost = false
    private var registrationGeneration = 0

    init(
        preferences: ShortcutPreferences,
        registrar: (any ShortcutRegistering)? = nil,
        onAddFinderSelection: @escaping () -> Void,
        onToggleShelf: @escaping () -> Void
    ) {
        self.preferences = preferences
        self.registrar = registrar ?? SystemShortcutRegistrar()
        self.onAddFinderSelection = onAddFinderSelection
        self.onToggleShelf = onToggleShelf
    }

    func start(finderIsFrontmost: Bool) {
        isStarted = true
        self.finderIsFrontmost = finderIsFrontmost
        resumeCurrentShortcuts()
    }

    func stop() {
        isStarted = false
        preferences.setRecording(nil)
        suspendShortcuts()
    }

    func updateFinderAvailability(_ isFrontmost: Bool) {
        finderIsFrontmost = isFrontmost
        guard isStarted, preferences.recordingAction == nil else { return }
        if isFrontmost, registrations[.addFinderSelection] == nil {
            if let registration = register(.addFinderSelection, binding: preferences.values.addFinderSelection) {
                registrations[.addFinderSelection] = registration
            } else {
                preferences.setError("Add Finder Selection is unavailable. Choose another shortcut.")
            }
        } else if !isFrontmost {
            registrations.removeValue(forKey: .addFinderSelection)?.invalidate()
        }
    }

    func beginRecording(_ action: ShelfShortcut) {
        suspendShortcuts()
        preferences.setError(nil)
        preferences.setRecording(action)
    }

    func cancelRecording(_ action: ShelfShortcut) {
        guard preferences.recordingAction == action else { return }
        preferences.setRecording(nil)
        resumeCurrentShortcuts()
    }

    @discardableResult
    func setShortcut(_ binding: ShortcutBinding, for action: ShelfShortcut) -> Bool {
        apply(preferences.values.replacing(action, with: binding))
    }

    @discardableResult
    func restoreDefaults() -> Bool {
        apply(.defaults)
    }

    private func apply(_ candidate: ShortcutConfiguration) -> Bool {
        if candidate == preferences.values {
            preferences.setError(nil)
            preferences.setRecording(nil)
            resumeCurrentShortcuts()
            return true
        }
        if let message = candidate.validationMessage {
            return reject(message)
        }
        for action in ShelfShortcut.allCases where registrar.isReserved(candidate.binding(for: action)) {
            return reject("That shortcut is used by macOS. Choose another.")
        }

        suspendShortcuts()
        var staged: [ShelfShortcut: any ShortcutRegistration] = [:]
        for action in ShelfShortcut.allCases {
            guard let registration = register(action, binding: candidate.binding(for: action)) else {
                for registration in staged.values { registration.invalidate() }
                return reject("That shortcut is unavailable. Choose another.")
            }
            staged[action] = registration
        }

        preferences.commit(candidate)
        preferences.setError(nil)
        preferences.setRecording(nil)
        if isStarted {
            registrations = staged
            if !finderIsFrontmost {
                registrations.removeValue(forKey: .addFinderSelection)?.invalidate()
            }
        } else {
            for registration in staged.values { registration.invalidate() }
        }
        return true
    }

    private func reject(_ message: String) -> Bool {
        suspendShortcuts()
        preferences.setRecording(nil)
        resumeCurrentShortcuts()
        preferences.setError(message)
        return false
    }

    private func register(_ action: ShelfShortcut, binding: ShortcutBinding) -> (any ShortcutRegistration)? {
        let generation = registrationGeneration
        return registrar.register(action, binding: binding) { [weak self] in
            guard let self, self.isStarted, self.preferences.recordingAction == nil,
                  self.registrationGeneration == generation else { return }
            switch action {
            case .addFinderSelection:
                guard self.finderIsFrontmost else { return }
                self.onAddFinderSelection()
            case .toggleShelf:
                self.onToggleShelf()
            }
        }
    }

    private func resumeCurrentShortcuts() {
        guard isStarted, preferences.recordingAction == nil else { return }
        if registrations[.toggleShelf] == nil {
            if let registration = register(.toggleShelf, binding: preferences.values.toggleShelf) {
                registrations[.toggleShelf] = registration
            } else {
                preferences.setError("Show or Hide Shelf is unavailable. Choose another shortcut.")
            }
        }
        updateFinderAvailability(finderIsFrontmost)
    }

    private func suspendShortcuts() {
        registrationGeneration += 1
        for registration in registrations.values { registration.invalidate() }
        registrations.removeAll()
    }
}
