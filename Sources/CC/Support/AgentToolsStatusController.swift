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

    var isConfigured: Bool {
        [status, cli, codex, claude].allSatisfy { $0 == .upToDate }
            && (legacyCLI == .absent || legacyCLI == .unrelated)
    }

    var canSetUp: Bool {
        [.notInstalled, .outdated].contains(status)
            && [cli, codex, claude].allSatisfy { [.upToDate, .notInstalled, .outdated].contains($0) }
            && legacyCLI != .unknown
    }

    var message: String {
        switch status {
        case .upToDate: isConfigured ? "AI tools are configured." : "AI tool status needs another check."
        case .notInstalled: "AI tools are not set up."
        case .outdated: "AI tools need an update."
        case .userModified: "A skill was edited. Review your changes before setup."
        case .blocked: "Existing files or links need review before setup."
        case .unknown: "Couldn’t check AI tools."
        }
    }

    var menuNotice: String? {
        switch status {
        case .notInstalled: "Set Up AI Tools"
        case .outdated: "Update AI Tools"
        default: nil
        }
    }
}

private enum AgentToolsProcess {
    static func make(appURL: URL, homeURL: URL, arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            appURL.appendingPathComponent("Contents/Resources/install_agent_tools.sh").path
        ] + arguments
        // The bundled installer owns destination checks and rollback. Shell startup files,
        // exported functions, and a caller's PATH must not influence its work.
        process.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "CC_INSTALL_APP": appURL.path,
            "CC_INSTALL_HOME": homeURL.path
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return process
    }
}

struct AgentToolsChecker: Sendable {
    let appURL: URL
    let homeURL: URL

    func check() -> AgentToolsReport {
        let process = AgentToolsProcess.make(appURL: appURL, homeURL: homeURL, arguments: ["--check"])
        let output = Pipe()
        process.standardOutput = output
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationReason == .exit, process.terminationStatus == 0 else { return .unknown }
            return try JSONDecoder().decode(AgentToolsReport.self, from: data)
        } catch {
            return .unknown
        }
    }
}

struct AgentToolsInstaller: Sendable {
    let appURL: URL
    let homeURL: URL

    func install() -> Bool {
        let process = AgentToolsProcess.make(appURL: appURL, homeURL: homeURL, arguments: [])
        process.standardOutput = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationReason == .exit && process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

@MainActor
final class AgentToolsStatusController: ObservableObject {
    @Published private(set) var report: AgentToolsReport?
    @Published private(set) var isChecking = false
    @Published private(set) var isInstalling = false
    @Published private(set) var operationMessage: String?
    @Published private(set) var errorMessage: String?

    private struct CachedCheck: Codable {
        let version: String
        let report: AgentToolsReport
    }

    private static let cacheKey = "agentToolsLastCheck"
    private let defaults: UserDefaults
    private let version: String
    private let checker: @Sendable () async -> AgentToolsReport
    private let installer: @Sendable () async -> Bool
    private var checkedVersion: String?
    private var task: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        version: String? = nil,
        installer: (@Sendable () async -> Bool)? = nil,
        checker: (@Sendable () async -> AgentToolsReport)? = nil
    ) {
        self.defaults = defaults
        let bundle = Bundle.main
        self.version = version ?? [
            bundle.bundleURL.path,
            bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
            bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        ].joined(separator: "|")
        let appURL = bundle.bundleURL
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let service = AgentToolsChecker(appURL: appURL, homeURL: homeURL)
        let setup = AgentToolsInstaller(appURL: appURL, homeURL: homeURL)
        self.checker = checker ?? {
            await Task.detached(priority: .utility) { service.check() }.value
        }
        self.installer = installer ?? {
            await Task.detached(priority: .userInitiated) { setup.install() }.value
        }
        if let data = defaults.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode(CachedCheck.self, from: data),
           cached.version == self.version,
           cached.report.status != .unknown {
            report = cached.report
            checkedVersion = cached.version
        }
    }

    var isWorking: Bool { isChecking || isInstalling }
    var canSetUp: Bool { !isWorking && report?.canSetUp == true }
    var setupTitle: String { report?.status == .outdated ? "Update" : "Set Up" }

    var message: String {
        if isInstalling { return "Configuring AI tools…" }
        if isChecking { return "Checking AI tools…" }
        return (report ?? .unknown).message
    }

    func checkAfterVersionChange() {
        guard checkedVersion != version else { return }
        refresh()
    }

    func refresh() {
        guard task == nil else { return }
        operationMessage = nil
        errorMessage = nil
        isChecking = true
        let checker = checker
        task = Task { [weak self] in
            let result = await checker()
            guard let self else { return }
            publish(result)
            isChecking = false
            task = nil
        }
    }

    func setUp() {
        guard task == nil, canSetUp else { return }
        operationMessage = nil
        errorMessage = nil
        isInstalling = true
        let installer = installer
        let checker = checker
        task = Task { [weak self] in
            let finished = await installer()
            let result = await checker()
            guard let self else { return }
            publish(result)
            if finished && result.isConfigured {
                operationMessage = "AI tools are configured for Codex and Claude Code. Start a new assistant session."
            } else {
                errorMessage = finished
                    ? "Setup finished, but the tools could not be confirmed."
                    : "Setup did not complete."
            }
            isInstalling = false
            task = nil
        }
    }

    private func publish(_ result: AgentToolsReport) {
        report = result
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
