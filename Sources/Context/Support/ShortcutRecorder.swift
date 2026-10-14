import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    let binding: ShortcutBinding
    let isRecording: Bool
    let actionName: String
    let onBegin: () -> Void
    let onCancel: () -> Void
    let onRecord: (ShortcutBinding) -> Void

    func makeNSView(context: NSViewRepresentableContext<ShortcutRecorder>) -> ShortcutRecorderButton {
        ShortcutRecorderButton()
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: NSViewRepresentableContext<ShortcutRecorder>) {
        button.onBegin = onBegin
        button.onCancel = onCancel
        button.onRecord = onRecord
        button.title = isRecording ? "Press shortcut…" : binding.displayString
        button.setAccessibilityLabel("Shortcut for \(actionName)")
        button.setAccessibilityValue(isRecording ? "Recording" : binding.accessibilityString)
        button.toolTip = isRecording ? "Press a shortcut. Escape cancels." : "Click to change this shortcut."
        button.setRecording(isRecording)
    }

    static func dismantleNSView(_ button: ShortcutRecorderButton, coordinator: ()) {
        button.cancelRecording()
    }
}

final class ShortcutRecorderButton: NSButton {
    var onBegin: () -> Void = {}
    var onCancel: () -> Void = {}
    var onRecord: (ShortcutBinding) -> Void = { _ in }
    private var isRecording = false
    private var eventMonitor: Any?
    private var windowObservers: [NSObjectProtocol] = []

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        target = self
        action = #selector(pressed)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc private func pressed() {
        if isRecording {
            cancelRecording()
        } else {
            onBegin()
        }
    }

    func setRecording(_ recording: Bool) {
        guard recording != isRecording else { return }
        isRecording = recording
        if recording {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }

    func cancelRecording() {
        guard isRecording else { return }
        isRecording = false
        stopMonitoring()
        onCancel()
    }

    override func resignFirstResponder() -> Bool {
        cancelRecording()
        return super.resignFirstResponder()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { cancelRecording() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func keyDown(with event: NSEvent) {
        if isRecording {
            record(event)
        } else {
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        record(event)
        return true
    }

    private func startMonitoring() {
        guard let window, window.makeFirstResponder(self) else {
            cancelRecording()
            return
        }
        // A local monitor receives Command chords before window/menu key
        // equivalents such as Command-W can close Settings.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording, event.window === self.window,
                  self.window?.isKeyWindow == true, self.window?.firstResponder === self else { return event }
            self.record(event)
            return nil
        }
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main
            ) { [weak self] _ in
                self?.cancelRecording()
            })
        }
    }

    private func record(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        let binding = ShortcutBinding(event: event)
        if event.keyCode == UInt16(kVK_Escape), binding.modifiers == 0 {
            cancelRecording()
            return
        }
        isRecording = false
        stopMonitoring()
        onRecord(binding)
    }

    private func stopMonitoring() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
        windowObservers.removeAll()
    }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
    }
}
