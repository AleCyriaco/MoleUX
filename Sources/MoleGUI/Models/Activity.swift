import Foundation

/// Live state of one section's long-running work.
///
/// This lives in `AppState`, not in the view, so a running clean survives a tab
/// switch: SwiftUI tears down the detail view when the sidebar selection
/// changes, and any `@State` output would go with it. Sections are independent,
/// so each keeps its own record and they run in parallel.
struct Activity: Equatable {
    /// What is running right now, shown next to the spinner ("Preview", "Cleaning").
    var label: String = ""
    var isRunning: Bool = false
    var output: String = ""
    var exitCode: Int32?
    var startedAt: Date?
    var finishedAt: Date?
    /// Cancellation handle for the CLI process backing this run.
    var token: UUID?

    var isDryRun: Bool = false

    /// True once a run has produced something worth keeping on screen.
    var hasResult: Bool { !output.isEmpty || exitCode != nil }

    var succeeded: Bool? {
        guard let exitCode else { return nil }
        return exitCode == 0
    }

    var duration: TimeInterval? {
        guard let startedAt else { return nil }
        return (finishedAt ?? Date()).timeIntervalSince(startedAt)
    }

    var durationLabel: String? {
        guard let duration else { return nil }
        if duration < 60 { return String(format: "%.0fs", duration) }
        return String(format: "%dm %02ds", Int(duration) / 60, Int(duration) % 60)
    }

    mutating func begin(label: String, dryRun: Bool, token: UUID) {
        self.label = label
        self.isDryRun = dryRun
        self.token = token
        isRunning = true
        output = ""
        exitCode = nil
        startedAt = Date()
        finishedAt = nil
    }

    mutating func finish(exitCode: Int32) {
        isRunning = false
        self.exitCode = exitCode
        finishedAt = Date()
        token = nil
    }
}
