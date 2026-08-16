import AppKit
import Foundation
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    enum Section: String, CaseIterable, Identifiable, Hashable {
        case dashboard = "Dashboard"
        case clean = "Clean"
        case uninstall = "Uninstall"
        case optimize = "Optimize"
        case purge = "Purge"
        case installer = "Installers"
        case analyze = "Analyze"
        case status = "Live Status"
        case history = "History"
        case settings = "Settings"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .dashboard: return "house.fill"
            case .clean: return "trash.fill"
            case .uninstall: return "app.badge.checkmark"
            case .optimize: return "bolt.circle.fill"
            case .purge: return "folder.badge.minus"
            case .installer: return "shippingbox.fill"
            case .analyze: return "chart.pie.fill"
            case .status: return "heart.text.square.fill"
            case .history: return "clock.arrow.circlepath"
            case .settings: return "gearshape.fill"
            }
        }

        var subtitle: String {
            switch self {
            case .dashboard: return "Overview & quick actions"
            case .clean: return "Preview and free disk space"
            case .uninstall: return "Remove apps + leftovers"
            case .optimize: return "Refresh caches & services"
            case .purge: return "Old project build artifacts"
            case .installer: return "DMG / PKG leftovers"
            case .analyze: return "Explore disk usage"
            case .status: return "CPU, memory, disk, network"
            case .history: return "Past cleanup sessions"
            case .settings: return "CLI path and preferences"
            }
        }
    }

    private enum DefaultsKey {
        static let molePath = "mole.gui.molePath"
        static let refreshSeconds = "mole.gui.refreshSeconds"
        static let adminPromptSeen = "mole.gui.adminPromptSeen"
    }

    @Published var section: Section = .dashboard
    @Published var molePath: String
    @Published var status: StatusMetrics?
    @Published var history: HistoryPayload?
    @Published var installedApps: [InstalledApp] = []
    @Published var isLoadingStatus = false
    @Published var isLoadingApps = false
    /// Per-section run state — survives tab switches, one entry per section.
    @Published var activities: [Section: Activity] = [:]
    @Published var lastError: String?
    @Published var lastCommandLog: String = ""
    @Published var moleVersion: String = "—"
    @Published var moleAvailable = false
    @Published var liveRefreshSeconds: Double
    @Published var adminState: AdminAccess.State = .unavailable
    /// Drives the one-time explainer shown when the app cannot elevate.
    @Published var showAdminPrompt = false

    // Section state lives here, not in the views: SwiftUI discards the detail
    // view on every sidebar change, and with it any @State the user built up.
    @Published var uninstallSelection = Set<String>()
    @Published var uninstallQuery = ""
    @Published var uninstallPermanent = false

    @Published var installerFiles: [InstallerFile] = []
    @Published var installerSelection = Set<String>()
    @Published var installerStatus = ""
    @Published var installerScanned = false

    @Published var analyzePath: String = NSHomeDirectory()
    @Published var analyzePayload: AnalyzePayload?
    @Published var analyzeStack: [String] = []

    let cli: MoleCLI
    private var statusTimer: AnyCancellable?

    init(cli: MoleCLI = MoleCLI()) {
        self.cli = cli
        let defaults = UserDefaults.standard
        let savedPath = defaults.string(forKey: DefaultsKey.molePath) ?? ""
        if !savedPath.isEmpty {
            cli.customMolePath = savedPath
        }
        let savedRefresh = defaults.double(forKey: DefaultsKey.refreshSeconds)
        self.liveRefreshSeconds = savedRefresh >= 2 ? savedRefresh : 5
        // Resolution probes candidate binaries — bootstrap() does it off-main.
        self.molePath = savedPath
        Task {
            await bootstrap()
        }
    }

    func bootstrap() async {
        await detectMole()
        await refreshAdminState()
        await refreshStatus()
        await refreshHistory()
        startLiveStatus(interval: liveRefreshSeconds)

        // Ask once, at launch, rather than failing silently mid-clean.
        let defaults = UserDefaults.standard
        if !adminState.canElevate, !defaults.bool(forKey: DefaultsKey.adminPromptSeen) {
            showAdminPrompt = true
            defaults.set(true, forKey: DefaultsKey.adminPromptSeen)
        }
    }

    func refreshAdminState() async {
        adminState = await AdminAccess.current()
    }

    /// Opens `mo touchid`, the CLI's own Touch ID setup, in Terminal — it edits
    /// the sudo PAM stack, which needs a real admin prompt.
    func enableTouchID() {
        openInTerminal(["touchid"])
    }

    func detectMole() async {
        cli.invalidateResolvedPath()
        if let path = await cli.resolveMolePath() {
            molePath = path
            moleAvailable = true
            moleVersion = (try? await cli.version()) ?? "unknown"
        } else {
            moleAvailable = false
            moleVersion = "not found"
            lastError = "Mole CLI not found. Install with `brew install mole` or set the path in Settings."
        }
    }

    func refreshStatus() async {
        guard moleAvailable || cli.resolvedMolePath != nil else { return }
        isLoadingStatus = true
        defer { isLoadingStatus = false }
        do {
            status = try await cli.fetchStatus()
            lastError = nil
        } catch {
            // Don't clobber a destructive-command error with a poll failure.
            if !hasRunningWork {
                lastError = error.localizedDescription
            }
        }
    }

    func refreshHistory() async {
        do {
            history = try await cli.fetchHistory(limit: 40)
        } catch {
            if history == nil, !hasRunningWork {
                lastError = error.localizedDescription
            }
        }
    }

    func refreshInstalledApps() async {
        isLoadingApps = true
        defer { isLoadingApps = false }

        // The native scan always runs: it is fast, and it is what keeps the list
        // complete when the CLI's own scan gives up early.
        async let nativeScan = InstalledAppScanner.scan()
        var cliApps: [InstalledApp] = []
        var cliError: String?
        if moleAvailable || cli.resolvedMolePath != nil {
            do {
                cliApps = try await cli.fetchInstalledApps()
            } catch {
                cliError = error.localizedDescription
            }
        }

        let native = await nativeScan
        installedApps = InstalledAppScanner.merge(cli: cliApps, native: native)

        if installedApps.isEmpty, let cliError {
            lastError = cliError
        } else {
            lastError = nil
        }

        await fillMissingSizes()
    }

    /// Apps the CLI never reached arrive without a size — resolve them in the
    /// background so the table is populated without blocking the first render.
    private func fillMissingSizes() async {
        let pending = installedApps.filter { $0.size == nil }.map(\.path)
        guard !pending.isEmpty else { return }
        for path in pending {
            guard let size = await InstalledAppScanner.size(of: path) else { continue }
            guard let index = installedApps.firstIndex(where: { $0.path == path }) else { continue }
            installedApps[index].size = size
        }
    }

    func startLiveStatus(interval: TimeInterval = 5) {
        let clamped = min(max(interval, 2), 60)
        liveRefreshSeconds = clamped
        UserDefaults.standard.set(clamped, forKey: DefaultsKey.refreshSeconds)
        statusTimer?.cancel()
        statusTimer = Timer.publish(every: clamped, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                guard !self.hasRunningWork else { return }
                Task { await self.refreshStatus() }
            }
    }

    func stopLiveStatus() {
        statusTimer?.cancel()
        statusTimer = nil
    }

    // MARK: - Section activities

    func activity(_ section: Section) -> Activity {
        activities[section] ?? Activity()
    }

    func isRunning(_ section: Section) -> Bool {
        activities[section]?.isRunning == true
    }

    /// Marks a section busy around work the GUI does itself (native scans), so
    /// the sidebar spinner covers those too.
    func withActivity<T>(_ section: Section, label: String, _ work: () async -> T) async -> T {
        var record = activities[section] ?? Activity()
        record.label = label
        record.isRunning = true
        record.startedAt = record.startedAt ?? Date()
        record.finishedAt = nil
        activities[section] = record

        let value = await work()

        activities[section]?.isRunning = false
        activities[section]?.finishedAt = Date()
        return value
    }

    /// Any section busy — used to pause status polling while work is in flight.
    var hasRunningWork: Bool {
        activities.values.contains { $0.isRunning }
    }

    func cancel(_ section: Section) {
        guard let token = activities[section]?.token else { return }
        cli.cancel(token)
        activities[section]?.output += "\n… cancelling\n"
    }

    func clearOutput(_ section: Section) {
        guard activities[section]?.isRunning != true else { return }
        activities[section] = Activity()
    }

    // MARK: - Commands

    func runClean(dryRun: Bool) async {
        await runSectionCommand(
            .clean,
            command: "clean",
            args: dryRun ? ["--dry-run"] : [],
            label: dryRun ? "Previewing" : "Cleaning",
            dryRun: dryRun
        )
    }

    func runOptimize(dryRun: Bool) async {
        await runSectionCommand(
            .optimize,
            command: "optimize",
            args: dryRun ? ["--dry-run"] : [],
            label: dryRun ? "Previewing" : "Optimizing",
            dryRun: dryRun
        )
    }

    func runPurge(dryRun: Bool) async {
        await runSectionCommand(
            .purge,
            command: "purge",
            args: dryRun ? ["--dry-run"] : [],
            label: dryRun ? "Previewing" : "Purging",
            dryRun: dryRun
        )
    }

    /// Uninstall one or more apps (by uninstall_name).
    /// `mo uninstall NAME…` asks "Proceed with uninstallation? [y/N]" on stdin —
    /// with no answer it reads EOF and aborts, so the GUI confirms for the user.
    /// The SwiftUI confirmation dialog is what actually gates this.
    func runUninstall(apps: [String], dryRun: Bool, permanent: Bool = false) async {
        guard !apps.isEmpty else { return }
        var args = apps
        if dryRun { args.insert("--dry-run", at: 0) }
        if permanent { args.insert("--permanent", at: 0) }
        await runSectionCommand(
            .uninstall,
            command: "uninstall",
            args: args,
            label: dryRun ? "Previewing" : "Uninstalling",
            dryRun: dryRun,
            stdinText: "y\n",
            header: (dryRun ? "Previewing uninstall for " : "Uninstalling ") + apps.joined(separator: ", ") + "\n\n"
        )
    }

    /// Runs a CLI command as `section`'s activity: output streams into the
    /// shared record, so leaving the tab neither stops it nor loses it.
    /// Sections are independent — two of these can be in flight at once.
    @discardableResult
    func runSectionCommand(
        _ section: Section,
        command: String,
        args: [String] = [],
        label: String,
        dryRun: Bool = false,
        stdinText: String? = nil,
        header: String = ""
    ) async -> CommandResult {
        guard activities[section]?.isRunning != true else {
            return CommandResult(exitCode: -1, stdout: "", stderr: "Already running")
        }

        let token = UUID()
        var record = Activity()
        record.begin(label: label, dryRun: dryRun, token: token)
        record.output = header
        activities[section] = record

        let result = await runTracked(section, command: command, args: args, stdinText: stdinText, token: token)

        activities[section]?.finish(exitCode: result.exitCode)
        if activities[section]?.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            activities[section]?.output = result.combinedOutput
        }
        lastCommandLog = result.combinedOutput

        if result.exitCode != 0, result.exitCode != 130 {
            lastError = "\(command) exited with code \(result.exitCode)"
        } else {
            lastError = nil
        }

        if ["clean", "optimize", "uninstall", "purge"].contains(command) {
            await refreshHistory()
            await refreshStatus()
            if command == "uninstall" {
                await refreshInstalledApps()
            }
        }
        return result
    }

    private func runTracked(
        _ section: Section,
        command: String,
        args: [String],
        stdinText: String?,
        token: UUID
    ) async -> CommandResult {
        do {
            return try await cli.runStreaming(
                command: command,
                args: args,
                stdinText: stdinText,
                token: token
            ) { [weak self] chunk in
                Task { @MainActor in
                    self?.activities[section]?.output += chunk
                }
            }
        } catch let error as MoleCLIError {
            if case .cancelled = error {
                return CommandResult(exitCode: 130, stdout: "", stderr: "Cancelled.")
            }
            lastError = error.localizedDescription
            return CommandResult(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        } catch {
            lastError = error.localizedDescription
            return CommandResult(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }
    }

    // MARK: - Installers (native scan, Trash removal)

    func scanInstallers() async {
        installerStatus = ""
        let found = await withActivity(.installer, label: "Scanning") {
            await InstallerScanner.scan()
        }
        installerFiles = found
        installerSelection = installerSelection.filter { id in found.contains { $0.id == id } }
        installerScanned = true
    }

    func trashInstallers(_ targets: [InstallerFile]) async {
        guard !targets.isEmpty else { return }
        let freed = targets.reduce(UInt64(0)) { $0 + $1.size }
        let failures = await withActivity(.installer, label: "Moving to Trash") {
            await InstallerScanner.moveToTrash(targets)
        }

        let failedIds = Set(failures.map { $0.0.id })
        installerFiles.removeAll { targets.contains($0) && !failedIds.contains($0.id) }
        installerSelection = failedIds

        if failures.isEmpty {
            installerStatus = "Moved \(targets.count) to Trash · \(ByteFormat.string(freed)) freed"
        } else {
            installerStatus = "Moved \(targets.count - failures.count) to Trash · \(failures.count) failed"
            lastError = "Could not trash \(failures[0].0.name): \(failures[0].1)"
        }
        await refreshStatus()
    }

    // MARK: - Analyze

    func runAnalyze(path: String? = nil) async {
        if let path { analyzePath = path }
        let target = analyzePath
        guard !target.isEmpty else { return }

        let token = UUID()
        var record = activities[.analyze] ?? Activity()
        record.begin(label: "Scanning \(URL(fileURLWithPath: target).lastPathComponent)", dryRun: false, token: token)
        activities[.analyze] = record

        do {
            analyzePayload = try await cli.fetchAnalyze(path: target, token: token)
            activities[.analyze]?.finish(exitCode: 0)
            lastError = nil
        } catch {
            analyzePayload = nil
            activities[.analyze]?.finish(exitCode: 1)
            if case MoleCLIError.cancelled = error {
                activities[.analyze]?.exitCode = 130
            } else {
                lastError = error.localizedDescription
            }
        }
    }

    func analyzeDrill(into path: String) async {
        analyzeStack.append(analyzePath)
        await runAnalyze(path: path)
    }

    func analyzeGoUp() async {
        if let previous = analyzeStack.popLast() {
            await runAnalyze(path: previous)
            return
        }
        let parent = URL(fileURLWithPath: analyzePath).deletingLastPathComponent().path
        guard parent != analyzePath else { return }
        await runAnalyze(path: parent)
    }

    func updateMolePath(_ path: String) {
        molePath = path
        cli.customMolePath = path.isEmpty ? nil : path
        UserDefaults.standard.set(path, forKey: DefaultsKey.molePath)
        Task { await detectMole(); await refreshStatus() }
    }

    func revealMoleHome() {
        guard !molePath.isEmpty else { return }
        let url = URL(fileURLWithPath: molePath).deletingLastPathComponent()
        NSWorkspace.shared.open(url)
    }

    func openInTerminal(_ arguments: [String]) {
        guard let mole = cli.resolvedMolePath else {
            lastError = "Mole CLI not found. Set the path in Settings."
            return
        }
        let joined = ([mole] + arguments).map(shellQuoted).joined(separator: " ")
        let script = """
        tell application "Terminal"
            activate
            do script "\(joined.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))"
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let errPipe = Pipe()
        process.standardError = errPipe
        do {
            try process.run()
        } catch {
            lastError = "Could not open Terminal: \(error.localizedDescription)"
            return
        }
        // Apple Events are gated by TCC — surface the denial instead of
        // leaving the button looking dead.
        DispatchQueue.global(qos: .utility).async {
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus != 0 else { return }
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            Task { @MainActor in
                self.lastError = message.isEmpty
                    ? "Terminal refused the request. Allow Mole under System Settings › Privacy & Security › Automation."
                    : "Terminal: \(message)"
            }
        }
    }

    private func shellQuoted(_ argument: String) -> String {
        guard argument.contains(where: { " \t\"'\\$`*?()[]{};&|<>!#~".contains($0) }) else { return argument }
        return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
