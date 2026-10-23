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

    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    general
                    Divider()
                    ShelfOpeningSettings(preferences: openingPreferences)
                    Divider()
                    shortcuts
                    Divider()
                    agentToolsSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .font(.system(size: 13, weight: .regular))
        .controlSize(.regular)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var general: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Shelf")
                Spacer(minLength: 12)
                Picker("Shelf Location", selection: $preferences.mode) {
                    Text("Menu Bar").tag(ShelfPresentationMode.menuBar)
                    Text("Notch").tag(ShelfPresentationMode.notch)
                        .disabled(!preferences.hasNotchedDisplay)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 180, alignment: .trailing)
            }
            .frame(minHeight: 32)

            HStack {
                Text("Sound for AI items")
                Spacer(minLength: 12)
                Toggle("Play Sound When Agents Add Items", isOn: $soundPreferences.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .frame(minHeight: 32)
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 0) {
            shortcutRow("Add selection", action: .addFinderSelection)
            shortcutRow("Show shelf", action: .toggleShelf)

            if let message = shortcutPreferences.errorMessage {
                Text(message)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.red)
                    .accessibilityLabel("Shortcut error: \(message)")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func shortcutRow(_ title: String, action: ShelfShortcut) -> some View {
        HStack {
            Text(title)
            if action == .toggleShelf,
               shortcutPreferences.values != .defaults || shortcutPreferences.recordingAction != nil {
                Button("Reset") { shortcutController.restoreDefaults() }
                    .buttonStyle(.link)
                    .controlSize(.small)
                    .accessibilityLabel("Restore Default Shortcuts")
            }
            Spacer(minLength: 12)
            ShortcutRecorder(
                binding: shortcutPreferences.values.binding(for: action),
                isRecording: shortcutPreferences.recordingAction == action,
                actionName: action == .addFinderSelection ? "Add Finder Selection" : "Show or Hide Shelf",
                onBegin: { shortcutController.beginRecording(action) },
                onCancel: { shortcutController.cancelRecording(action) },
                onRecord: { shortcutController.setShortcut($0, for: action) }
            )
            .frame(width: 180, height: 28, alignment: .trailing)
        }
        .frame(minHeight: 32)
    }

    private var footer: some View {
        HStack {
            Button("Updates…", action: onCheckForUpdates)
                .disabled(agentTools.isWorking)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
                .disabled(agentTools.isWorking)
        }
        .frame(minHeight: 28)
    }

    private var agentToolsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("AI Tools")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                if let aggregateStatus {
                    Text(aggregateStatus)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if agentTools.report?.isConfigured != true {
                    Button(agentTools.setupTitle) { agentTools.setUp() }
                        .disabled(!agentTools.canSetUp)
                }
                Button { agentTools.refresh() } label: {
                    Group {
                        if agentTools.isWorking {
                            ProgressView()
                                .controlSize(.mini)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .medium))
                        }
                    }
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(agentTools.isWorking)
                .accessibilityLabel("Check AI Tools")
                .help("Check AI tools")
            }
            .frame(minHeight: 32)

            HStack(spacing: 16) {
                toolStatus("CLI", status: agentTools.report?.cli ?? .unknown)
                toolStatus("Codex", status: agentTools.report?.codex ?? .unknown)
                toolStatus("Claude Code", status: agentTools.report?.claude ?? .unknown)
            }
            .frame(minHeight: 20)

            if let message = agentTools.errorMessage {
                statusMessage(message, isWarning: true)
            }
            if let message = reviewReason, message != agentTools.errorMessage {
                statusMessage(message, isWarning: true)
            }
            if let message = agentTools.operationMessage {
                statusMessage(message, isWarning: false)
            }
        }
    }

    private var aggregateStatus: String? {
        if agentTools.isInstalling { return "Setting up…" }
        if agentTools.isChecking { return "Checking…" }
        guard let report = agentTools.report else { return "Unavailable" }
        if report.isConfigured { return nil }
        return report.status == .upToDate ? "Needs review" : toolStatusTitle(report.status)
    }

    private var reviewReason: String? {
        guard !agentTools.isWorking, let report = agentTools.report else { return nil }
        switch report.status {
        case .userModified, .blocked, .unknown: return report.message
        case .upToDate: return report.isConfigured ? nil : report.message
        case .notInstalled, .outdated: return nil
        }
    }

    private func statusMessage(_ message: String, isWarning: Bool) -> some View {
        Text(message)
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(isWarning ? .orange : .secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func toolStatus(_ title: String, status: AgentToolsReport.Status) -> some View {
        HStack(spacing: 6) {
            Text(title)
            Image(systemName: toolStatusSymbol(status))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(status == .blocked || status == .userModified ? .orange : .secondary)
                .accessibilityHidden(true)
        }
        .font(.system(size: 12, weight: .regular))
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("\(title): \(toolStatusTitle(status))")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(toolStatusTitle(status))
    }

    private func toolStatusSymbol(_ status: AgentToolsReport.Status) -> String {
        switch status {
        case .upToDate: "checkmark"
        case .notInstalled: "circle"
        case .outdated: "arrow.triangle.2.circlepath"
        case .userModified, .blocked: "exclamationmark.triangle"
        case .unknown: "questionmark.circle"
        }
    }

    private func toolStatusTitle(_ status: AgentToolsReport.Status) -> String {
        switch status {
        case .upToDate: "Configured"
        case .notInstalled: "Not set up"
        case .outdated: "Update available"
        case .userModified, .blocked: "Needs review"
        case .unknown: "Unavailable"
        }
    }
}
