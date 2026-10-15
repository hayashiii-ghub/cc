import Combine
import Foundation

struct AgentToolsReport: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case upToDate = "up-to-date"
        case notInstalled = "not-installed"
        case outdated
        case userModified = "user-modified"
        case blocked
        case unknown
    }

    enum LegacyCLI: String, Codable, Sendable {
        case absent, managed, unrelated, unknown
    }

    let status: Status
    let cli: Status
    let codex: Status
    let claude: Status
    let legacyCLI: LegacyCLI

    enum CodingKeys: String, CodingKey {
        case status, cli, codex, claude
        case legacyCLI = "legacy_cli"
    }

    static let unknown = AgentToolsReport(
        status: .unknown, cli: .unknown, codex: .unknown, claude: .unknown, legacyCLI: .unknown
    )

    var message: String {
        switch status {
        case .upToDate: "Agent tools are up to date."
        case .notInstalled: "Agent tools are not installed. Run the command below to set them up."
        case .outdated: "Agent tools need an update. Run the command below."
        case .userModified: "A skill was edited. Review your changes before running the installer."
        case .blocked: "Existing files or links prevent installation. Review them before running the installer."
        case .unknown: "Couldn’t check agent tools. Review the installer plan in Terminal."
        }
    }

    var menuNotice: String? {
        switch status {
        case .notInstalled: "Set Up Agent Tools…"
        case .outdated: "Update Agent Tools…"
        default: nil
        }
    }
}

struct AgentToolsChecker: Sendable {
    let appURL: URL
    let homeURL: URL

    func check() -> AgentToolsReport {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            appURL.appendingPathComponent("Contents/Resources/install_agent_tools.sh").path,
            "--check"
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["CC_INSTALL_APP"] = appURL.path
        environment["CC_INSTALL_HOME"] = homeURL.path
        process.environment = environment
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return .unknown }
            return try JSONDecoder().decode(AgentToolsReport.self, from: data)
        } catch {
            return .unknown
        }
    }
}

@MainActor
final class AgentToolsStatusController: ObservableObject {
    @Published private(set) var report: AgentToolsReport?
    @Published private(set) var isChecking = false

    private struct CachedCheck: Codable {
        let version: String
        let report: AgentToolsReport
    }

    private static let cacheKey = "agentToolsLastCheck"
    private let defaults: UserDefaults
    private let version: String
    private let checker: @Sendable () async -> AgentToolsReport
    private var checkedVersion: String?
    private var task: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        version: String? = nil,
        checker: (@Sendable () async -> AgentToolsReport)? = nil
    ) {
        self.defaults = defaults
        let bundle = Bundle.main
        self.version = version ?? [
            bundle.bundleURL.path,
            bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
            bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        ].joined(separator: "|")
        let service = AgentToolsChecker(
            appURL: bundle.bundleURL,
            homeURL: FileManager.default.homeDirectoryForCurrentUser
        )
        self.checker = checker ?? {
            await Task.detached(priority: .utility) { service.check() }.value
        }
        if let data = defaults.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode(CachedCheck.self, from: data),
           cached.version == self.version,
           cached.report.status != .unknown {
            report = cached.report
            checkedVersion = cached.version
        }
    }

    var message: String {
        isChecking ? "Checking agent tools…" : (report ?? .unknown).message
    }

    func checkAfterVersionChange() {
        guard checkedVersion != version else { return }
        refresh()
    }

    func refresh() {
        guard task == nil else { return }
        isChecking = true
        let checker = checker
        task = Task { [weak self] in
            let result = await checker()
            guard let self else { return }
            report = result
            isChecking = false
            task = nil
            if result.status != .unknown {
                checkedVersion = version
                if let data = try? JSONEncoder().encode(CachedCheck(version: version, report: result)) {
                    defaults.set(data, forKey: Self.cacheKey)
                }
            } else {
                checkedVersion = nil
                defaults.removeObject(forKey: Self.cacheKey)
            }
        }
    }
}
