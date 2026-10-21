import AppKit
import SwiftUI

@MainActor
struct SettingsView: View {
    @ObservedObject var preferences: ShelfPresentationPreferences
    @ObservedObject var openingPreferences: ShelfOpenPreferences
    @ObservedObject var soundPreferences: ShelfSoundPreferences
    @ObservedObject var shortcutPreferences: ShortcutPreferences
    @ObservedObject var agentTools: AgentToolsStatusController
    let shortcutController: ShortcutController
    let onCheckForUpdates: () -> Void
    let onOpenReleasePage: () -> Void

    private var installCommand: String {
        let appPath = Bundle.main.bundleURL.path
        let scriptPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/install_agent_tools.sh").path
        return "CC_INSTALL_APP=\(shellQuote(appPath)) bash \(shellQuote(scriptPath))"
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    var body: some View {
        Form {
            Section {
                appHeader
            }

            general
            ShelfOpeningSettings(preferences: openingPreferences)
            shortcuts
            agentToolsSection
            updates
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            CCMark()
                .fill(.primary)
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)

            Text("cc:")
                .font(.headline)
        }
    }

    private var general: some View {
        Section("General") {
            Picker("Shelf Location", selection: $preferences.mode) {
                Text("Menu Bar").tag(ShelfPresentationMode.menuBar)
                Text("Notch").tag(ShelfPresentationMode.notch)
                    .disabled(!preferences.hasNotchedDisplay)
            }
            .pickerStyle(.menu)

            Toggle("Play Sound When Agents Add Items", isOn: $soundPreferences.isEnabled)
                .toggleStyle(.switch)
        }
    }

    private var shortcuts: some View {
        Section {
            shortcutRow(
                "Add Finder Selection",
                action: .addFinderSelection
            )
            shortcutRow(
                "Show or Hide Shelf",
                action: .toggleShelf
            )
            Button("Restore Defaults") {
                shortcutController.restoreDefaults()
            }
            .disabled(shortcutPreferences.values == .defaults && shortcutPreferences.recordingAction == nil)
        } header: {
            Text("Shortcuts")
        } footer: {
            if let message = shortcutPreferences.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Shortcut error: \(message)")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func shortcutRow(
        _ title: String,
        action: ShelfShortcut
    ) -> some View {
        LabeledContent(title) {
            ShortcutRecorder(
                binding: shortcutPreferences.values.binding(for: action),
                isRecording: shortcutPreferences.recordingAction == action,
                actionName: title,
                onBegin: { shortcutController.beginRecording(action) },
                onCancel: { shortcutController.cancelRecording(action) },
                onRecord: { shortcutController.setShortcut($0, for: action) }
            )
            .frame(width: 150, height: 28)
        }
    }

    private var updates: some View {
        Section {
            HStack(spacing: 12) {
                Button("Check for Updates", action: onCheckForUpdates)

                Button(action: onOpenReleasePage) {
                    Label("Release Notes", systemImage: "arrow.up.right")
                }
                .buttonStyle(.link)
                .accessibilityLabel("Open cc: Release Notes")
            }
            .controlSize(.regular)
        } header: {
            Text("Updates")
        }
    }

    private var agentToolsSection: some View {
        Section("Agent Tools") {
            Text(agentTools.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(installCommand)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Copy Install Command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(installCommand, forType: .string)
            }
        }
    }
}
