import Foundation
import Testing
@testable import CC

@MainActor
struct AgentToolsStatusTests {
    @Test func checksOncePerVersionAndRestoresTheLastKnownState() async throws {
        let suite = "AgentToolsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let checks = CheckResults([report(.notInstalled), report(.upToDate)])
        let first = AgentToolsStatusController(defaults: defaults, version: "1", checker: { await checks.next() })
        first.checkAfterVersionChange()
        first.checkAfterVersionChange()
        try await finish(first)
        #expect(first.report?.status == .notInstalled)
        #expect(first.report?.menuNotice == "Set Up AI Tools")
        #expect(await checks.count == 1)

        let relaunched = AgentToolsStatusController(defaults: defaults, version: "1", checker: { await checks.next() })
        #expect(relaunched.report?.status == .notInstalled)
        relaunched.checkAfterVersionChange()
        #expect(!relaunched.isChecking)
        #expect(await checks.count == 1)

        let updated = AgentToolsStatusController(defaults: defaults, version: "2", checker: { await checks.next() })
        #expect(updated.report == nil)
        updated.checkAfterVersionChange()
        try await finish(updated)
        #expect(updated.report?.status == .upToDate)
        #expect(updated.report?.menuNotice == nil)
        #expect(await checks.count == 2)
    }

    @Test func openingSettingsRefreshesTheSameVersionAndCoalescesOverlappingChecks() async throws {
        let suite = "AgentToolsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let checks = CheckResults([report(.outdated), report(.upToDate)])
        let controller = AgentToolsStatusController(defaults: defaults, version: "1", checker: { await checks.next() })
        controller.checkAfterVersionChange()
        try await finish(controller)
        #expect(controller.report?.menuNotice == "Update AI Tools")

        controller.refresh()
        controller.refresh()
        #expect(controller.isChecking)
        try await finish(controller)
        #expect(await checks.count == 2)
        #expect(controller.report?.status == .upToDate)
        #expect(controller.report?.menuNotice == nil)
    }

    @Test func failedChecksStayUnknownAndDoNotSuppressTheNextLaunchCheck() async throws {
        let suite = "AgentToolsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let checks = CheckResults([report(.upToDate), .unknown, report(.userModified)])
        let first = AgentToolsStatusController(defaults: defaults, version: "1", checker: { await checks.next() })
        first.checkAfterVersionChange()
        try await finish(first)
        #expect(first.report?.status == .upToDate)
        first.refresh()
        try await finish(first)
        #expect(first.report?.status == .unknown)
        #expect(first.report?.menuNotice == nil)

        let relaunched = AgentToolsStatusController(defaults: defaults, version: "1", checker: { await checks.next() })
        #expect(relaunched.report == nil)
        relaunched.checkAfterVersionChange()
        try await finish(relaunched)
        #expect(await checks.count == 3)
        #expect(relaunched.report?.status == .userModified)
        #expect(relaunched.report?.message.contains("Review your changes") == true)
        #expect(relaunched.report?.menuNotice == nil)
    }

    @Test func checkerUsesExplicitPathsAndRejectsInvalidOrFailedOutput() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-agent-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Other App's Folder/cc.app")
        let home = root.appendingPathComponent("Other User's Home")
        let resources = app.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let script = resources.appendingPathComponent("install_agent_tools.sh")
        let body = """
        #!/bin/bash
        [[ "$#" == 1 && "$1" == --check ]] || exit 8
        [[ "$CC_INSTALL_APP/Contents/Resources/install_agent_tools.sh" == "$0" ]] || exit 9
        [[ -d "$CC_INSTALL_HOME" && "$CC_INSTALL_HOME" == *"Other User's Home" ]] || exit 10
        printf '%s\\n' '{"status":"outdated","cli":"up-to-date","codex":"outdated","claude":"not-installed","legacy_cli":"managed"}'
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        let checker = AgentToolsChecker(appURL: app, homeURL: home)
        let valid = await Task.detached { checker.check() }.value
        #expect(valid.status == .outdated)
        #expect(valid.cli == .upToDate)
        #expect(valid.codex == .outdated)
        #expect(valid.claude == .notInstalled)
        #expect(valid.legacyCLI == .managed)

        try "printf '%s\\n' 'not-json'".write(to: script, atomically: true, encoding: .utf8)
        #expect(await Task.detached { checker.check() }.value == .unknown)
        try (body + "\nexit 1\n").write(to: script, atomically: true, encoding: .utf8)
        #expect(await Task.detached { checker.check() }.value == .unknown)
        try FileManager.default.removeItem(at: script)
        #expect(await Task.detached { checker.check() }.value == .unknown)
    }

    @Test func setupSucceedsOnlyAfterTheInstallerAndFreshReadbackComplete() async throws {
        let suite = "AgentToolsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let actions = SetupActions(reports: [report(.notInstalled), report(.upToDate)], installSucceeds: true)
        let controller = AgentToolsStatusController(defaults: defaults, version: "1",
            installer: { await actions.install() }, checker: { await actions.check() })
        controller.refresh()
        try await finish(controller)
        controller.setUp()
        #expect(controller.isInstalling && controller.isWorking)
        #expect(controller.operationMessage == nil)
        try await finish(controller)
        #expect(controller.report?.isConfigured == true)
        #expect(controller.operationMessage?.contains("Codex and Claude Code") == true)
        #expect(controller.errorMessage == nil)
        #expect(await actions.events == ["check", "install", "check"])
    }

    @Test func anInstallerFailureStillRechecksButNeverClaimsSuccess() async throws {
        let suite = "AgentToolsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let actions = SetupActions(reports: [report(.outdated), report(.upToDate)], installSucceeds: false)
        let controller = AgentToolsStatusController(defaults: defaults, version: "1",
            installer: { await actions.install() }, checker: { await actions.check() })
        controller.refresh()
        try await finish(controller)
        #expect(controller.setupTitle == "Update")
        controller.setUp()
        try await finish(controller)
        #expect(controller.report?.isConfigured == true)
        #expect(controller.operationMessage == nil)
        #expect(controller.errorMessage?.contains("did not complete") == true)
        #expect(await actions.events == ["check", "install", "check"])
    }

    @Test(arguments: [
        AgentToolsReport.unknown,
        AgentToolsReport(status: .outdated, cli: .upToDate, codex: .outdated, claude: .upToDate, legacyCLI: .absent),
        AgentToolsReport(status: .upToDate, cli: .upToDate, codex: .upToDate, claude: .notInstalled, legacyCLI: .absent),
        AgentToolsReport(status: .upToDate, cli: .upToDate, codex: .upToDate, claude: .upToDate, legacyCLI: .managed)
    ])
    func anExitZeroWithoutCompleteReadbackIsNotSuccess(_ readback: AgentToolsReport) async throws {
        let suite = "AgentToolsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let actions = SetupActions(reports: [report(.notInstalled), readback], installSucceeds: true)
        let controller = AgentToolsStatusController(defaults: defaults, version: "1",
            installer: { await actions.install() }, checker: { await actions.check() })
        controller.refresh()
        try await finish(controller)
        controller.setUp()
        try await finish(controller)
        #expect(controller.report == readback)
        #expect(controller.operationMessage == nil)
        #expect(controller.errorMessage?.contains("could not be confirmed") == true)
        #expect(controller.message != "AI tools are configured.")
    }

    @Test func repeatedSetupAndRefreshCannotOverlapTheInstallOrItsReadback() async throws {
        let suite = "AgentToolsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let actions = SetupActions(reports: [report(.notInstalled), report(.upToDate)], installSucceeds: true, holdInstall: true)
        let controller = AgentToolsStatusController(defaults: defaults, version: "1",
            installer: { await actions.install() }, checker: { await actions.check() })
        controller.refresh()
        try await finish(controller)
        controller.setUp()
        controller.setUp()
        controller.refresh()
        for _ in 0..<200 {
            if await actions.events.contains("install") { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(controller.isInstalling && !controller.canSetUp)
        #expect(await actions.events == ["check", "install"])
        #expect(controller.operationMessage == nil)
        await actions.releaseInstall()
        try await finish(controller)
        #expect(await actions.events == ["check", "install", "check"])
        #expect(controller.operationMessage != nil)
    }

    @Test(arguments: [AgentToolsReport.Status.unknown, .blocked, .userModified, .upToDate])
    func setupRejectsUnverifiedProtectedAndAlreadyConfiguredStates(_ status: AgentToolsReport.Status) async throws {
        let suite = "AgentToolsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let actions = SetupActions(reports: [report(status)], installSucceeds: true)
        let controller = AgentToolsStatusController(defaults: defaults, version: "1",
            installer: { await actions.install() }, checker: { await actions.check() })
        controller.refresh()
        try await finish(controller)
        #expect(!controller.canSetUp)
        controller.setUp()
        await Task.yield()
        #expect(!controller.isWorking)
        #expect(await actions.events == ["check"])
        #expect(controller.operationMessage == nil)
    }

    @Test func checkAgainAfterFailedSetupClearsFeedbackAndPublishesFreshState() async throws {
        let suite = "AgentToolsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let actions = SetupActions(reports: [report(.notInstalled), .unknown, report(.upToDate)], installSucceeds: false)
        let controller = AgentToolsStatusController(defaults: defaults, version: "1",
            installer: { await actions.install() }, checker: { await actions.check() })
        controller.refresh()
        try await finish(controller)
        controller.setUp()
        try await finish(controller)
        #expect(controller.errorMessage != nil)
        controller.refresh()
        try await finish(controller)
        #expect(controller.errorMessage == nil && controller.operationMessage == nil)
        #expect(controller.report?.isConfigured == true)
        #expect(await actions.events == ["check", "install", "check", "check"])
    }

    @Test func installerAndCheckerUseTheSameExplicitTargetsAndCleanChildEnvironment() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cc-agent-setup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Other App's Folder/cc.app")
        let home = root.appendingPathComponent("Other User's Home")
        let resources = app.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let script = resources.appendingPathComponent("install_agent_tools.sh")
        let body = """
        #!/bin/bash
        [[ "$PATH" == /usr/bin:/bin:/usr/sbin:/sbin ]] || exit 8
        [[ -z "${BASH_ENV+x}" && -z "${ENV+x}" ]] || exit 9
        [[ "$CC_INSTALL_APP/Contents/Resources/install_agent_tools.sh" == "$0" ]] || exit 10
        [[ "$CC_INSTALL_HOME" == *"Other User's Home" ]] || exit 11
        if [[ "$#" == 1 && "$1" == --check ]]; then
          if [[ -f "$CC_INSTALL_HOME/installed" ]]; then state=up-to-date; else state=not-installed; fi
          printf '{"status":"%s","cli":"%s","codex":"%s","claude":"%s","legacy_cli":"absent"}\\n' "$state" "$state" "$state" "$state"
        elif [[ "$#" == 0 ]]; then
          if IFS= read -r input; then exit 12; fi
          printf 'installer output is not a completion check\\n'
          printf 'installer diagnostic is not shown as UI text\\n' >&2
          printf configured >"$CC_INSTALL_HOME/installed"
        else
          exit 13
        fi
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        let checker = AgentToolsChecker(appURL: app, homeURL: home)
        let installer = AgentToolsInstaller(appURL: app, homeURL: home)
        #expect(await Task.detached { checker.check() }.value.status == .notInstalled)
        #expect(await Task.detached { installer.install() }.value)
        #expect(await Task.detached { checker.check() }.value.isConfigured)
        #expect(try String(contentsOf: home.appendingPathComponent("installed"), encoding: .utf8) == "configured")
        try "exit 42".write(to: script, atomically: true, encoding: .utf8)
        #expect(await Task.detached { !installer.install() }.value)
        try FileManager.default.removeItem(at: script)
        #expect(await Task.detached { !installer.install() }.value)
    }

    private func report(_ status: AgentToolsReport.Status) -> AgentToolsReport {
        AgentToolsReport(status: status, cli: status, codex: status, claude: status, legacyCLI: .absent)
    }

    private func finish(_ controller: AgentToolsStatusController) async throws {
        for _ in 0..<200 where controller.isWorking {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(!controller.isWorking)
    }
}

private actor CheckResults {
    private var reports: [AgentToolsReport]
    private(set) var count = 0

    init(_ reports: [AgentToolsReport]) { self.reports = reports }

    func next() -> AgentToolsReport {
        count += 1
        return reports.isEmpty ? .unknown : reports.removeFirst()
    }
}

private actor SetupActions {
    private var reports: [AgentToolsReport]
    private let installSucceeds: Bool
    private var holdInstall: Bool
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var events: [String] = []

    init(reports: [AgentToolsReport], installSucceeds: Bool, holdInstall: Bool = false) {
        self.reports = reports
        self.installSucceeds = installSucceeds
        self.holdInstall = holdInstall
    }

    func check() -> AgentToolsReport {
        events.append("check")
        return reports.isEmpty ? .unknown : reports.removeFirst()
    }

    func install() async -> Bool {
        events.append("install")
        if holdInstall { await withCheckedContinuation { continuation = $0 } }
        return installSucceeds
    }

    func releaseInstall() {
        holdInstall = false
        continuation?.resume()
        continuation = nil
    }
}
