import AppKit
import Carbon.HIToolbox
import Combine

struct ShortcutBinding: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let supportedModifiers = UInt32(cmdKey | optionKey | controlKey | shiftKey)
    private static let requiredModifiers = UInt32(cmdKey | optionKey | controlKey)
    private static let modifierKeyCodes: Set<UInt32> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
    private static let functionKeys: [UInt32: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18",
        80: "F19", 90: "F20"
    ]

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        let flags = event.modifierFlags
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        modifiers = value
    }

    var validationMessage: String? {
        guard keyCode < 128, !Self.modifierKeyCodes.contains(keyCode),
              modifiers & ~Self.supportedModifiers == 0 else {
            return "Choose a keyboard shortcut."
        }
        guard modifiers & Self.requiredModifiers != 0 || Self.functionKeys[keyCode] != nil else {
            return "Include Command, Option, or Control."
        }
        return nil
    }

    var displayString: String {
        var symbols = ""
        if modifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols.isEmpty ? keyName : "\(symbols) \(keyName)"
    }

    var accessibilityString: String {
        var names: [String] = []
        if modifiers & UInt32(controlKey) != 0 { names.append("Control") }
        if modifiers & UInt32(optionKey) != 0 { names.append("Option") }
        if modifiers & UInt32(shiftKey) != 0 { names.append("Shift") }
        if modifiers & UInt32(cmdKey) != 0 { names.append("Command") }
        names.append(keyName)
        return names.joined(separator: " ")
    }

    private var keyName: String {
        switch keyCode {
        case UInt32(kVK_Tab): return "Tab"
        case UInt32(kVK_Space): return "Space"
        case UInt32(kVK_Return): return "Return"
        case UInt32(kVK_ANSI_KeypadEnter): return "Enter"
        case UInt32(kVK_Escape): return "Escape"
        case UInt32(kVK_Delete): return "Delete"
        case UInt32(kVK_ForwardDelete): return "Forward Delete"
        case UInt32(kVK_LeftArrow): return "←"
        case UInt32(kVK_RightArrow): return "→"
        case UInt32(kVK_UpArrow): return "↑"
        case UInt32(kVK_DownArrow): return "↓"
        case UInt32(kVK_Home): return "Home"
        case UInt32(kVK_End): return "End"
        case UInt32(kVK_PageUp): return "Page Up"
        case UInt32(kVK_PageDown): return "Page Down"
        default: break
        }
        if let name = Self.functionKeys[keyCode] { return name }

        guard let inputSource = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let dataPointer = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
            return "Key \(keyCode)"
        }
        let data = unsafeBitCast(dataPointer, to: CFData.self)
        guard let bytes = CFDataGetBytePtr(data), CFDataGetLength(data) > 0 else { return "Key \(keyCode)" }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 8)
        let result = UCKeyTranslate(
            layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
            UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask),
            &deadKeyState, characters.count, &length, &characters
        )
        guard result == noErr, length > 0 else { return "Key \(keyCode)" }
        return String(decoding: characters.prefix(Int(length)), as: UTF16.self).uppercased()
    }
}

struct ShortcutConfiguration: Codable, Equatable {
    var addFinderSelection: ShortcutBinding
    var toggleShelf: ShortcutBinding

    static let defaults = ShortcutConfiguration(
        addFinderSelection: ShortcutBinding(keyCode: UInt32(kVK_Tab), modifiers: UInt32(optionKey)),
        toggleShelf: ShortcutBinding(keyCode: UInt32(kVK_Tab), modifiers: UInt32(optionKey | shiftKey))
    )

    func binding(for action: ShelfShortcut) -> ShortcutBinding {
        switch action {
        case .addFinderSelection: addFinderSelection
        case .toggleShelf: toggleShelf
        }
    }

    func replacing(_ action: ShelfShortcut, with binding: ShortcutBinding) -> ShortcutConfiguration {
        var value = self
        switch action {
        case .addFinderSelection: value.addFinderSelection = binding
        case .toggleShelf: value.toggleShelf = binding
        }
        return value
    }

    var validationMessage: String? {
        if let message = addFinderSelection.validationMessage ?? toggleShelf.validationMessage { return message }
        return addFinderSelection == toggleShelf ? "Choose a different shortcut for each action." : nil
    }
}

@MainActor
final class ShortcutPreferences: ObservableObject {
    private static let storageKey = "shelfShortcuts"
    private let defaults: UserDefaults

    @Published private(set) var values: ShortcutConfiguration
    @Published private(set) var recordingAction: ShelfShortcut?
    @Published private(set) var errorMessage: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(ShortcutConfiguration.self, from: data),
           saved.validationMessage == nil {
            values = saved
        } else {
            values = .defaults
        }
    }

    func commit(_ values: ShortcutConfiguration) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        defaults.set(data, forKey: Self.storageKey)
        self.values = values
    }

    func setRecording(_ action: ShelfShortcut?) {
        recordingAction = action
    }

    func setError(_ message: String?) {
        errorMessage = message
    }
}
