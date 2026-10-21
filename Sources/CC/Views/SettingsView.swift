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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                appHeader

                general
                settingsCard {
                    ShelfOpeningSettings(preferences: openingPreferences)
                }
                shortcuts
                agentToolsSection

                Divider()
                footer
            }
            .font(.body)
            .controlSize(.regular)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appHeader: some View {
        HStack {
            Text("cc:")
                .font(.title2.weight(.semibold))
            Spacer()
            Button("Check for Updates…", action: onCheckForUpdates)
        }
    }

    private var general: some View {
        settingsCard {
            Text("General")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            HStack {
                Text("Shelf Location")
                Spacer(minLength: 12)
                Picker("Shelf Location", selection: $preferences.mode) {
                    Text("Menu Bar").tag(ShelfPresentationMode.menuBar)
                    Text("Notch").tag(ShelfPresentationMode.notch)
                        .disabled(!preferences.hasNotchedDisplay)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 180)
            }

            HStack {
                Text("Play Sound When Agents Add Items")
                Spacer(minLength: 12)
                Toggle("Play Sound When Agents Add Items", isOn: $soundPreferences.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }

    private var shortcuts: some View {
        settingsCard {
            HStack {
                Text("Shortcuts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Restore Defaults") {
                    shortcutController.restoreDefaults()
                }
                .controlSize(.small)
                .disabled(shortcutPreferences.values == .defaults && shortcutPreferences.recordingAction == nil)
            }

            shortcutRow(
                "Add Finder Selection",
                action: .addFinderSelection
            )
            shortcutRow(
                "Show or Hide Shelf",
                action: .toggleShelf
            )

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
        HStack {
            Text(title)
            Spacer(minLength: 12)
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

    private var footer: some View {
        HStack {
            Button(action: onOpenReleasePage) {
                Label("Release Notes", systemImage: "arrow.up.right")
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open cc: Release Notes")
            Spacer()
            Button("Quit cc:") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    private var agentToolsSection: some View {
        settingsCard {
            Text("Agent Tools")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

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

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 24))
    }
}
