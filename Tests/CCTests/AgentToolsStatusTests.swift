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
        let first = AgentToolsStatusController(defaults: defaults, version: "1") { await checks.next() }
        first.checkAfterVersionChange()
        first.checkAfterVersionChange()
        try await finish(first)
        #expect(first.report?.status == .notInstalled)
        #expect(first.report?.menuNotice == "Set Up Agent Tools")
        #expect(await checks.count == 1)

        let relaunched = AgentToolsStatusController(defaults: defaults, version: "1") { await checks.next() }
        #expect(relaunched.report?.status == .notInstalled)
        relaunched.checkAfterVersionChange()
        #expect(!relaunched.isChecking)
        #expect(await checks.count == 1)

        let updated = AgentToolsStatusController(defaults: defaults, version: "2") { await checks.next() }
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
        let controller = AgentToolsStatusController(defaults: defaults, version: "1") { await checks.next() }
        controller.checkAfterVersionChange()
        try await finish(controller)
        #expect(controller.report?.menuNotice == "Update Agent Tools")

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
        let first = AgentToolsStatusController(defaults: defaults, version: "1") { await checks.next() }
        first.checkAfterVersionChange()
        try await finish(first)
        #expect(first.report?.status == .upToDate)
        first.refresh()
        try await finish(first)
        #expect(first.report?.status == .unknown)
        #expect(first.report?.menuNotice == nil)

        let relaunched = AgentToolsStatusController(defaults: defaults, version: "1") { await checks.next() }
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

    private func report(_ status: AgentToolsReport.Status) -> AgentToolsReport {
        AgentToolsReport(status: status, cli: status, codex: status, claude: status, legacyCLI: .absent)
    }

    private func finish(_ controller: AgentToolsStatusController) async throws {
        for _ in 0..<200 where controller.isChecking {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(!controller.isChecking)
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
