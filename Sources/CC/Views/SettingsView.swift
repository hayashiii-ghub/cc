import AppKit
import SwiftUI

@MainActor
struct SettingsView: View {
    @ObservedObject var openingPreferences: ShelfOpenPreferences
    @ObservedObject var soundPreferences: ShelfSoundPreferences
    @ObservedObject var shortcutPreferences: ShortcutPreferences
    @ObservedObject var agentTools: AgentToolsStatusController
    let shortcutController: ShortcutController
    let updates: AppUpdateController
    let onClose: () -> Void
    @State private var showsSettings = false

    /// Two screens in one panel: what you use every day, and behind the gear everything that is set once.
    var body: some View {
        Group {
            if showsSettings {
                settings
            } else {
                overview
            }
        }
        // Coming back from fixing a file elsewhere should not need a button press.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            agentTools.refresh()
        }
    }

    private var overview: some View {
        PanelChrome(title: "cc:", onClose: onClose) {
            GlassIconButton("Settings", systemImage: "gearshape", glyphSize: 16) {
                showsSettings = true
            }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                agentToolsSummary
                shortcuts
                ShelfOpeningSettings(preferences: openingPreferences)
            }
        } footer: {
            footer
        }
    }

    private var settings: some View {
        PanelChrome(title: "Settings", onBack: { showsSettings = false }, onClose: onClose) {
            GlassIconButton("Check AI tools", systemImage: "arrow.clockwise", glyphSize: 15) {
                agentTools.refresh()
            }
            .disabled(agentTools.isWorking)
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                agentToolsSection
                SystemSettingsSection(updates: updates)
            }
        } footer: {
            footer
        }
    }

    /// The same on both screens, so updating, help, and quitting never move.
    private var footer: some View {
        SettingsFooter(
            updates: updates,
            helpURL: URL(string: "https://github.com/hayashiii-ghub/cc#readme")!,
            isBusy: agentTools.isWorking
        )
    }

    /// Whether assistants can use the shelf, in one row; the per-tool breakdown is a setting.
    private var agentToolsSummary: some View {
        SettingsSection {
            SettingsRow(
                "AI Tools",
                detail: agentTools.errorMessage ?? agentTools.report?.blocker ?? reviewReason ?? aggregateStatus
                    ?? "Codex, Claude Code and Antigravity can use your shelf.",
                isWarning: agentTools.errorMessage != nil || reviewReason != nil
            ) {
                if let path = agentTools.report?.blockerPath {
                    // A Set Up button that cannot be pressed is a dead end; show what is in the way instead.
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                } else if agentTools.report?.isConfigured == true {
                    Image(systemName: "checkmark")
                        .font(SettingsStyle.statusSymbol)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Connected")
                } else {
                    Button(agentTools.setupTitle) { agentTools.setUp() }
                        .disabled(!agentTools.canSetUp)
                }
            }
        }
    }

    private var shortcuts: some View {
        SettingsSection("Shortcuts", accessory: resetShortcutsButton) {
            shortcutRow("Add Finder selection", action: .addFinderSelection)
                .help("Adds what’s selected while Finder is in front.")
            shortcutRow("Show shelf", action: .toggleShelf)
                .help("Opens or closes the shelf from any app.")
            if let message = shortcutPreferences.errorMessage {
                SettingsNote(message, isWarning: true)
                    .accessibilityLabel("Shortcut error: \(message)")
            }
        }
    }

    @ViewBuilder private var resetShortcutsButton: some View {
        if shortcutPreferences.values != .defaults || shortcutPreferences.recordingAction != nil {
            Button("Reset") { shortcutController.restoreDefaults() }
                .buttonStyle(.link)
                .controlSize(.small)
                .accessibilityLabel("Restore Default Shortcuts")
        }
    }

    private func shortcutRow(_ title: String, action: ShelfShortcut) -> some View {
        SettingsRow(title) {
            ShortcutRecorder(
                binding: shortcutPreferences.values.binding(for: action),
                isRecording: shortcutPreferences.recordingAction == action,
                actionName: action == .addFinderSelection ? "Add Finder Selection" : "Show or Hide Shelf",
                onBegin: { shortcutController.beginRecording(action) },
                onCancel: { shortcutController.cancelRecording(action) },
                onRecord: { shortcutController.setShortcut($0, for: action) }
            )
            .frame(width: 150, height: 24, alignment: .trailing)
        }
    }

    private var agentToolsSection: some View {
        let tools: [(title: String, status: AgentToolsReport.Status)] = [
            ("cc-shelf command", agentTools.report?.cli ?? .unknown),
            ("Codex", agentTools.report?.codex ?? .unknown),
            ("Claude Code", agentTools.report?.claude ?? .unknown),
            ("Antigravity", agentTools.report?.antigravity ?? .unknown)
        ]
        // The installer checks in this order and reports the first thing in its way, so the
        // explanation belongs under the first tool that needs review.
        let blocked = tools.first { $0.status == .blocked || $0.status == .userModified }?.title
        return SettingsSection("AI Tools") {
            ForEach(tools, id: \.title) { tool in
                toolStatus(tool.title, status: tool.status,
                           detail: tool.title == blocked ? agentTools.report?.blocker : nil)
            }
            if let message = agentTools.errorMessage {
                SettingsNote(message, isWarning: true)
            }
            if agentTools.report?.blocker == nil, let message = reviewReason, message != agentTools.errorMessage {
                SettingsNote(message, isWarning: true)
            }
            if let message = agentTools.operationMessage {
                SettingsNote(message)
            }
            SettingsToggle("Sound when agents add items", isOn: $soundPreferences.isEnabled)
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

    private func toolStatus(_ title: String, status: AgentToolsReport.Status, detail: String?) -> some View {
        let needsReview = status == .blocked || status == .userModified
        return SettingsRow(title, detail: detail, isWarning: true) {
            HStack(spacing: 6) {
                Text(toolStatusTitle(status))
                    .font(SettingsStyle.caption)
                Image(systemName: toolStatusSymbol(status))
                    .font(SettingsStyle.statusSymbol)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(needsReview ? Color.orange : Color.secondary)
        }
        .accessibilityElement(children: .combine)
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
        case .upToDate: "Connected"
        case .notInstalled: "Not set up"
        case .outdated: "Update available"
        case .userModified, .blocked: "Needs review"
        case .unknown: "Unavailable"
        }
    }
}
