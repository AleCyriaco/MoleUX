import Foundation

struct CommandResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var combinedOutput: String {
        let out = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let err = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.isEmpty { return err }
        if err.isEmpty { return out }
        return out + "\n\n--- stderr ---\n" + err
    }

    var succeeded: Bool { exitCode == 0 }
}

enum MoleCLIError: LocalizedError {
    case moleNotFound
    case invalidJSON(String)
    case launchFailed(String)
    case nonZeroExit(Int32, String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .moleNotFound:
            return "Mole CLI executable not found"
        case .invalidJSON(let detail):
            return "Failed to parse Mole JSON: \(detail)"
        case .launchFailed(let detail):
            return "Failed to launch Mole: \(detail)"
        case .nonZeroExit(let code, let output):
            return "Mole exited \(code): \(output.prefix(240))"
        case .cancelled:
            return "Command cancelled"
        }
    }
}

/// Thin bridge to the upstream Mole CLI / bundled Go helpers.
/// Prefer JSON surfaces (`status --json`, `history --json`, `uninstall --list`) when available.
final class MoleCLI: @unchecked Sendable {
    private let fileManager = FileManager.default
    /// Concurrent: sections run their commands in parallel, so a long clean
    /// must not hold up an analyze scan started from another tab.
    private let queue = DispatchQueue(label: "io.github.alecyriaco.moleux.cli", qos: .userInitiated, attributes: .concurrent)
    private let processLock = NSLock()
    /// Running processes by caller token, so one tab can be cancelled alone.
    private var activeProcesses: [UUID: Process] = [:]

    /// Optional override from Settings.
    var customMolePath: String? {
        didSet { invalidateResolvedPath() }
    }

    private let pathLock = NSLock()
    private var didResolvePath = false
    private var cachedMolePath: String?

    /// Workspace-relative clone used during development.
    private var workspaceMoleCandidates: [String] {
        let cwd = fileManager.currentDirectoryPath
        return [
            "\(cwd)/mole/mole",
            "\(cwd)/../mole/mole",
            "\(cwd)/../../mole/mole",
            // Harness layout: gui/mac is next to mole/
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Services
                .deletingLastPathComponent() // MoleGUI
                .deletingLastPathComponent() // Sources
                .deletingLastPathComponent() // mac
                .deletingLastPathComponent() // gui
                .appendingPathComponent("mole/mole")
                .path
        ]
    }

    /// Resolution probes candidates with a real subprocess, so the answer is
    /// cached until the path changes (Settings apply, re-detect).
    var resolvedMolePath: String? {
        pathLock.lock()
        defer { pathLock.unlock() }
        if didResolvePath { return cachedMolePath }
        cachedMolePath = discoverMolePath()
        didResolvePath = true
        return cachedMolePath
    }

    func invalidateResolvedPath() {
        pathLock.lock()
        didResolvePath = false
        cachedMolePath = nil
        pathLock.unlock()
    }

    /// Same as `resolvedMolePath`, off the main thread — the first resolution
    /// probes candidates with real subprocesses and must not stall the UI.
    func resolveMolePath() async -> String? {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.resolvedMolePath) }
        }
    }

    private func discoverMolePath() -> String? {
        let env = ProcessInfo.processInfo.environment
        var candidates: [String] = []
        if let custom = customMolePath, !custom.isEmpty { candidates.append(custom) }
        if let explicit = env["MOLE_PATH"], !explicit.isEmpty { candidates.append(explicit) }
        candidates += [
            "/opt/homebrew/bin/mo",
            "/opt/homebrew/bin/mole",
            "/usr/local/bin/mo",
            "/usr/local/bin/mole",
            "\(NSHomeDirectory())/.local/bin/mo",
            "\(NSHomeDirectory())/.local/bin/mole"
        ]
        candidates += workspaceMoleCandidates
        // Copy shipped inside the .app — last resort, a real install wins.
        if let bundled = env["MOLE_BUNDLED_PATH"], !bundled.isEmpty { candidates.append(bundled) }
        if let which = try? runProcess("/usr/bin/which", args: ["mo"]), which.succeeded {
            candidates.append(which.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        var seen = Set<String>()
        var firstExisting: String?
        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate) {
            let resolved = resolveSymlinks(candidate)
            guard seen.insert(resolved).inserted else { continue }
            if firstExisting == nil { firstExisting = resolved }
            if isWorkingMole(resolved) { return resolved }
        }
        // Nothing passed the probe: keep the first real file so the failure the
        // user sees comes from the CLI itself instead of a bare "not found".
        return firstExisting
    }

    /// The `mole` entry script is useless without its helper tree (`bin/`, `lib/`).
    /// `mole help` costs ~100ms and rejects broken copies — an incomplete bundle
    /// inside the .app would otherwise be picked and break every command.
    private func isWorkingMole(_ path: String) -> Bool {
        guard let result = try? runProcess(path, args: ["help"]) else { return false }
        return result.succeeded
    }

    /// Directory that contains the mole entry script (after symlink resolution).
    private var moleHome: String? {
        guard let path = resolvedMolePath else { return nil }
        return URL(fileURLWithPath: path).deletingLastPathComponent().path
    }

    /// Homebrew Cellar root when mole lives in `…/bin/mole` with helpers in `…/libexec/bin`.
    private var molePrefix: String? {
        guard let home = moleHome else { return nil }
        let url = URL(fileURLWithPath: home)
        if url.lastPathComponent == "bin" {
            return url.deletingLastPathComponent().path
        }
        return home
    }

    private var statusBinary: String? {
        guard let prefix = molePrefix, let home = moleHome else { return nil }
        let candidates = [
            "\(home)/bin/status-go",
            "\(prefix)/bin/status-go",
            "\(prefix)/libexec/bin/status-go",
            "\(home)/status-go",
            "\(home)/bin/status.sh",
            "\(prefix)/libexec/bin/status.sh"
        ]
        for path in candidates where fileManager.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    private var analyzeBinary: String? {
        guard let prefix = molePrefix, let home = moleHome else { return nil }
        let candidates = [
            "\(home)/bin/analyze-go",
            "\(prefix)/bin/analyze-go",
            "\(prefix)/libexec/bin/analyze-go"
        ]
        for path in candidates where fileManager.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    private func resolveSymlinks(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    func version() async throws -> String {
        let result = try await run(command: nil, args: ["--version"])
        let text = result.stdout + result.stderr
        if let match = text.range(of: #"\d+\.\d+\.\d+"#, options: .regularExpression) {
            return String(text[match])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func fetchStatus() async throws -> StatusMetrics {
        if let bin = statusBinary {
            let result = try await runAbsolute(bin, args: ["--json"])
            guard result.succeeded else {
                throw MoleCLIError.nonZeroExit(result.exitCode, result.combinedOutput)
            }
            return try decode(result.stdout)
        }

        let result = try await run(command: "status", args: ["--json"])
        guard result.succeeded else {
            throw MoleCLIError.nonZeroExit(result.exitCode, result.combinedOutput)
        }
        return try decode(result.stdout)
    }

    func fetchHistory(limit: Int = 20) async throws -> HistoryPayload {
        let result = try await run(command: "history", args: ["--json", "--limit", "\(limit)"])
        guard result.succeeded else {
            throw MoleCLIError.nonZeroExit(result.exitCode, result.combinedOutput)
        }
        return try decode(result.stdout)
    }

    /// `mo uninstall --list` → JSON array of installed apps.
    /// Some CLI builds abort partway through the scan (non-zero exit, array left
    /// unterminated). A short list beats an empty one, so the payload is decoded
    /// regardless of exit code and only a genuine parse failure throws.
    func fetchInstalledApps() async throws -> [InstalledApp] {
        let result = try await run(command: "uninstall", args: ["--list"])
        do {
            return try decode(result.stdout)
        } catch {
            if !result.succeeded {
                throw MoleCLIError.nonZeroExit(result.exitCode, result.combinedOutput)
            }
            throw error
        }
    }

    /// Disk usage snapshot via analyze-go --json (or `mo analyze PATH --json`).
    /// Takes a token: a scan over a large tree runs for minutes and has to stay
    /// cancellable from the tab that started it.
    func fetchAnalyze(path: String, token: UUID? = nil) async throws -> AnalyzePayload {
        if let bin = analyzeBinary {
            let result = try await runAbsolute(bin, args: ["--json", path], token: token)
            guard result.succeeded else {
                throw MoleCLIError.nonZeroExit(result.exitCode, result.combinedOutput)
            }
            return try decode(result.stdout)
        }
        // Go's flag parser stops at the first positional, so --json comes first.
        let result = try await run(command: "analyze", args: ["--json", path], token: token)
        guard result.succeeded else {
            throw MoleCLIError.nonZeroExit(result.exitCode, result.combinedOutput)
        }
        return try decode(result.stdout)
    }

    func run(
        command: String?,
        args: [String] = [],
        extraEnv: [String: String] = [:],
        stdinText: String? = nil,
        token: UUID? = nil
    ) async throws -> CommandResult {
        guard let mole = resolvedMolePath else { throw MoleCLIError.moleNotFound }
        return try await runAbsolute(
            mole,
            args: fullArgs(command, args),
            extraEnv: extraEnv,
            stdinText: stdinText,
            token: token
        )
    }

    /// Stream stdout/stderr line-by-line while a long command runs.
    func runStreaming(
        command: String?,
        args: [String] = [],
        extraEnv: [String: String] = [:],
        stdinText: String? = nil,
        token: UUID? = nil,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> CommandResult {
        guard let mole = resolvedMolePath else { throw MoleCLIError.moleNotFound }
        let allArgs = fullArgs(command, args)
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let result = try self.runProcessStreaming(
                        mole,
                        args: allArgs,
                        extraEnv: extraEnv,
                        stdinText: stdinText,
                        token: token,
                        onChunk: onChunk
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func fullArgs(_ command: String?, _ args: [String]) -> [String] {
        guard let command else { return args }
        return [command] + args
    }

    private func runAbsolute(
        _ executable: String,
        args: [String],
        extraEnv: [String: String] = [:],
        stdinText: String? = nil,
        token: UUID? = nil
    ) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let result = try self.runProcess(
                        executable,
                        args: args,
                        extraEnv: extraEnv,
                        stdinText: stdinText,
                        token: token
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Terminate the run started with `token`, leaving other tabs alone.
    func cancel(_ token: UUID) {
        processLock.lock()
        let process = activeProcesses[token]
        processLock.unlock()
        terminate(process)
    }

    func cancelAll() {
        processLock.lock()
        let processes = Array(activeProcesses.values)
        processLock.unlock()
        processes.forEach(terminate)
    }

    private func terminate(_ process: Process?) {
        guard let process, process.isRunning else { return }
        process.terminate()
        // Escalate if the process ignores SIGTERM briefly.
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if process.isRunning {
                process.interrupt()
            }
        }
    }

    private func track(_ process: Process, token: UUID?) {
        guard let token else { return }
        processLock.lock()
        activeProcesses[token] = process
        processLock.unlock()
    }

    private func untrack(token: UUID?) {
        guard let token else { return }
        processLock.lock()
        activeProcesses[token] = nil
        processLock.unlock()
    }

    @discardableResult
    private func runProcess(
        _ executable: String,
        args: [String],
        extraEnv: [String: String] = [:],
        stdinText: String? = nil,
        token: UUID? = nil
    ) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.environment = makeEnvironment(extraEnv)

        let inPipe = stdinText.map { _ in Pipe() }
        process.standardInput = inPipe ?? FileHandle.nullDevice

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            throw MoleCLIError.launchFailed(error.localizedDescription)
        }

        track(process, token: token)
        defer { untrack(token: token) }

        feed(stdinText, into: inPipe)

        // Drain both pipes *while* the child runs. Reading only after
        // waitUntilExit() deadlocks the moment output fills the 64KB pipe
        // buffer — `analyze --json` on a large folder emits far more than that.
        let lock = NSLock()
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        for (pipe, isStdout) in [(outPipe, true), (errPipe, false)] {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                lock.lock()
                if isStdout { outData = data } else { errData = data }
                lock.unlock()
                group.leave()
            }
        }

        process.waitUntilExit()
        group.wait()

        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""

        if process.terminationReason == .uncaughtSignal {
            throw MoleCLIError.cancelled
        }
        return CommandResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    /// Answer a CLI prompt non-interactively (e.g. uninstall's `[y/N]`).
    /// Written off the calling thread so a child that never reads can't block us.
    private func feed(_ text: String?, into pipe: Pipe?) {
        guard let text, let pipe else { return }
        DispatchQueue.global(qos: .utility).async {
            let handle = pipe.fileHandleForWriting
            try? handle.write(contentsOf: Data(text.utf8))
            try? handle.close()
        }
    }

    private func runProcessStreaming(
        _ executable: String,
        args: [String],
        extraEnv: [String: String],
        stdinText: String? = nil,
        token: UUID? = nil,
        onChunk: @escaping @Sendable (String) -> Void
    ) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.environment = makeEnvironment(extraEnv)

        let inPipe = stdinText.map { _ in Pipe() }
        process.standardInput = inPipe ?? FileHandle.nullDevice

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        var stdoutAll = ""
        var stderrAll = ""
        let lock = NSLock()

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            lock.lock(); stdoutAll += chunk; lock.unlock()
            onChunk(self.stripANSI(chunk))
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            lock.lock(); stderrAll += chunk; lock.unlock()
            onChunk(self.stripANSI(chunk))
        }

        do {
            try process.run()
        } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            throw MoleCLIError.launchFailed(error.localizedDescription)
        }

        track(process, token: token)
        defer { untrack(token: token) }

        feed(stdinText, into: inPipe)

        process.waitUntilExit()

        // Detach the handlers before draining, otherwise they race the final
        // read and the same bytes land in the console twice.
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil

        // Drain any remaining buffered data.
        let restOut = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let restErr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if !restOut.isEmpty {
            stdoutAll += restOut
            onChunk(stripANSI(restOut))
        }
        if !restErr.isEmpty {
            stderrAll += restErr
            onChunk(stripANSI(restErr))
        }

        if process.terminationReason == .uncaughtSignal {
            throw MoleCLIError.cancelled
        }
        return CommandResult(exitCode: process.terminationStatus, stdout: stdoutAll, stderr: stderrAll)
    }

    private func makeEnvironment(_ extraEnv: [String: String]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Force non-interactive, UTF-8, no color for parsing.
        env["TERM"] = "dumb"
        env["NO_COLOR"] = "1"
        env["MO_NO_COLOR"] = "1"
        env["LC_ALL"] = "C"
        env["LANG"] = "C"
        // Avoid interactive sudo prompts hanging the GUI.
        env["SUDO_ASKPASS"] = env["SUDO_ASKPASS"] ?? "/usr/bin/false"
        for (k, v) in extraEnv { env[k] = v }
        return env
    }

    private func decode<T: Decodable>(_ raw: String) throws -> T {
        let cleaned = extractJSON(stripANSI(raw))
        guard let data = cleaned.data(using: .utf8), !data.isEmpty else {
            throw MoleCLIError.invalidJSON("empty payload")
        }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            if let salvaged = truncatedArrayFix(cleaned)?.data(using: .utf8),
               let recovered = try? decoder.decode(T.self, from: salvaged) {
                return recovered
            }
            let preview = cleaned.prefix(160).replacingOccurrences(of: "\n", with: " ")
            throw MoleCLIError.invalidJSON("\(error.localizedDescription) · near: \(preview)")
        }
    }

    /// A CLI that dies mid-scan leaves `[ {...}, {...},` with no closing bracket.
    /// Cut back to the last complete object and close the array so the rows it
    /// did produce still reach the UI.
    private func truncatedArrayFix(_ text: String) -> String? {
        guard text.hasPrefix("["), !text.hasSuffix("]") else { return nil }
        guard let lastObject = text.range(of: "}", options: .backwards) else { return nil }
        return String(text[text.startIndex..<lastObject.upperBound]) + "]"
    }

    /// Pull the first JSON object/array out of mixed CLI output (banners, warnings).
    private func extractJSON(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return trimmed
        }
        if let obj = trimmed.range(of: "{"),
           let end = trimmed.range(of: "}", options: .backwards),
           obj.lowerBound < end.upperBound {
            return String(trimmed[obj.lowerBound..<end.upperBound])
        }
        if let arr = trimmed.range(of: "["),
           let end = trimmed.range(of: "]", options: .backwards),
           arr.lowerBound < end.upperBound {
            return String(trimmed[arr.lowerBound..<end.upperBound])
        }
        return trimmed
    }

    private func stripANSI(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\u001B\\[[0-9;]*[a-zA-Z]", options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }
}
