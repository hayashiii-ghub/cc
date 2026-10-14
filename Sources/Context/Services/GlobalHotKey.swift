import Carbon.HIToolbox
import Foundation
import OSLog

private let shortcutLogger = Logger(
    subsystem: "work.hayashigoto.Context",
    category: "Shortcuts"
)

enum ShelfShortcut: CaseIterable, Hashable {
    case addFinderSelection
    case toggleShelf

    private static let signature: OSType = 0x53484450

    var keyCode: UInt32 {
        ShortcutConfiguration.defaults.binding(for: self).keyCode
    }

    var modifiers: UInt32 {
        ShortcutConfiguration.defaults.binding(for: self).modifiers
    }

    var identifier: EventHotKeyID {
        switch self {
        case .addFinderSelection:
            EventHotKeyID(signature: Self.signature, id: 1)
        case .toggleShelf:
            EventHotKeyID(signature: Self.signature, id: 2)
        }
    }

    var logName: String {
        switch self {
        case .addFinderSelection:
            "Option-Tab"
        case .toggleShelf:
            "Option-Shift-Tab"
        }
    }

    func matches(_ identifier: EventHotKeyID) -> Bool {
        let expected = self.identifier
        return identifier.signature == expected.signature && identifier.id == expected.id
    }
}

final class GlobalHotKey: ShortcutRegistration {
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?
    private let shortcut: ShelfShortcut
    private let binding: ShortcutBinding
    private let action: () -> Void

    init?(shortcut: ShelfShortcut, binding: ShortcutBinding? = nil, action: @escaping () -> Void) {
        self.shortcut = shortcut
        self.binding = binding ?? ShortcutConfiguration.defaults.binding(for: shortcut)
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<GlobalHotKey>
                    .fromOpaque(context)
                    .takeUnretainedValue()

                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard status == noErr, hotKey.shortcut.matches(identifier) else {
                    return OSStatus(eventNotHandledErr)
                }

                hotKey.performAction()
                return noErr
            },
            1,
            &eventType,
            context,
            &eventHandlerReference
        )

        guard handlerStatus == noErr else { return nil }

        let registrationStatus = RegisterEventHotKey(
            self.binding.keyCode,
            self.binding.modifiers,
            shortcut.identifier,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &hotKeyReference
        )

        guard registrationStatus == noErr else {
            if let eventHandlerReference {
                RemoveEventHandler(eventHandlerReference)
                self.eventHandlerReference = nil
            }
            return nil
        }
    }

    deinit {
        invalidate()
    }

    func invalidate() {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
            self.hotKeyReference = nil
        }
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
            self.eventHandlerReference = nil
        }
    }

    private func performAction() {
        shortcutLogger.info("\(self.binding.displayString, privacy: .public) received")
        DispatchQueue.main.async {
            self.action()
        }
    }
}

struct SystemShortcutRegistrar: ShortcutRegistering {
    func register(
        _ action: ShelfShortcut,
        binding: ShortcutBinding,
        handler: @escaping () -> Void
    ) -> (any ShortcutRegistration)? {
        GlobalHotKey(shortcut: action, binding: binding, action: handler)
    }

    func isReserved(_ binding: ShortcutBinding) -> Bool {
        var hotKeys: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&hotKeys) == noErr,
              let dictionaries = hotKeys?.takeRetainedValue() as? [[String: Any]] else { return false }
        return dictionaries.contains { value in
            (value[kHISymbolicHotKeyEnabled as String] as? NSNumber)?.boolValue == true
                && (value[kHISymbolicHotKeyCode as String] as? NSNumber)?.uint32Value == binding.keyCode
                && (((value[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.uint32Value ?? 0)
                    & ShortcutBinding.supportedModifiers) == binding.modifiers
        }
    }
}
