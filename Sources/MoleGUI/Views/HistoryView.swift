import AppKit
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    SectionHeader(
                        title: "History",
                        subtitle: "Cleanup sessions and deletion log from Mole’s operation records."
                    )
                    Spacer()
                    Button {
                        Task { await appState.refreshHistory() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }

                if let history = appState.history {
                    sessions(history.sessions)
                    deletions(history.deletions)
                    if let logs = history.logs {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Log files")
                                .font(.headline)
                            if let ops = logs.operations {
                                logRow(ops)
                            }
                            if let dels = logs.deletions {
                                logRow(dels)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No history yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Run a clean, uninstall, or optimize to populate history.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 240)
                }
            }
            .padding(24)
        }
        .navigationTitle("History")
    }

    private func sessions(_ items: [HistorySession]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sessions")
                .font(.headline)
            if items.isEmpty {
                Text("No sessions recorded.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { s in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(s.command.capitalized)
                                .font(.headline)
                            Spacer()
                            Text(s.size ?? "—")
                                .fontWeight(.semibold)
                        }
                        HStack {
                            Text(s.startedAt)
                            if let end = s.endedAt, !end.isEmpty {
                                Text("→ \(end)")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        HStack(spacing: 16) {
                            label("Items", "\(s.items ?? 0)")
                            label("Ops", "\(s.operationCount ?? 0)")
                            label("Failed", "\(s.failedTasks ?? 0)")
                            if let a = s.actions {
                                label("Trashed", "\(a.trashed ?? 0)")
                                label("Removed", "\(a.removed ?? 0)")
                            }
                        }
                        .font(.caption)
                    }
                    .padding(14)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func deletions(_ items: [HistoryDeletion]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent deletions")
                .font(.headline)
            ForEach(items.prefix(40)) { d in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: d.mode == "trash" ? "trash" : "xmark.bin")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.path)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(2)
                        Text("\(d.timestamp) · \(d.mode ?? "?") · \(d.status ?? "?")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(d.sizeLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private func label(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .fontWeight(.medium)
        }
    }

    private func logRow(_ path: String) -> some View {
        Button {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        } label: {
            HStack {
                Image(systemName: "doc.text")
                Text(path)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
