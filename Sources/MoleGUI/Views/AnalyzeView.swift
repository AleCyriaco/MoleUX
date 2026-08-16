import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AnalyzeView: View {
    @EnvironmentObject private var appState: AppState
    // Scans run for minutes on large trees, so path, result, and breadcrumb
    // all live in AppState — leaving the tab must not restart or lose them.
    private var payload: AnalyzePayload? { appState.analyzePayload }
    private var isLoading: Bool { appState.isRunning(.analyze) }
    private var pathStack: [String] { appState.analyzeStack }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader(
                    title: "Analyze",
                    subtitle: "Explore disk usage. Tap a folder to drill down, or open the full TUI in Terminal."
                )

                if let disks = appState.status?.disks, !disks.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                        ForEach(disks) { disk in
                            Button {
                                appState.analyzeStack = []
                                Task { await appState.runAnalyze(path: disk.mount) }
                            } label: {
                                MetricCard(
                                    title: disk.mount,
                                    value: String(format: "%.0f%%", disk.usedPercent),
                                    subtitle: "\(ByteFormat.string(disk.freeBytes)) free · \(disk.fstype)",
                                    systemImage: disk.external ? "externaldrive" : "internaldrive",
                                    progress: disk.usedPercent / 100,
                                    tint: disk.usedPercent > 90 ? .red : .orange
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                pathControls

                if !pathStack.isEmpty {
                    breadcrumb
                }

                if isLoading {
                    ProgressView("Scanning…")
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else if let payload {
                    entriesList(payload)
                } else {
                    ContentUnavailableView(
                        "Pick a path",
                        systemImage: "folder.badge.questionmark",
                        description: Text("Scan a folder to see the largest entries.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 180)
                }
            }
            .padding(24)
        }
        .navigationTitle("Analyze")
    }

    private var pathControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Path")
                .font(.headline)
            HStack {
                TextField("Absolute path", text: $appState.analyzePath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Button("Browse…") { browse() }
                Button {
                    Task { await appState.runAnalyze() }
                } label: {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Scan", systemImage: "magnifyingglass")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || appState.analyzePath.isEmpty || !appState.moleAvailable)

                if isLoading {
                    Button(role: .destructive) {
                        appState.cancel(.analyze)
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    appState.openInTerminal(["analyze", appState.analyzePath])
                } label: {
                    Label("Open TUI", systemImage: "terminal")
                }
                .disabled(!appState.moleAvailable)
            }

            HStack(spacing: 8) {
                ForEach(quickPaths, id: \.path) { item in
                    Button(item.label) {
                        appState.analyzeStack = []
                        Task { await appState.runAnalyze(path: item.path) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            Button {
                Task { await appState.analyzeGoUp() }
            } label: {
                Label("Up", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Text(appState.analyzePath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private var quickPaths: [(label: String, path: String)] {
        let home = NSHomeDirectory()
        return [
            ("Home", home),
            ("Library", "\(home)/Library"),
            ("Caches", "\(home)/Library/Caches"),
            ("Downloads", "\(home)/Downloads"),
            ("Applications", "/Applications")
        ]
    }

    private func entriesList(_ payload: AnalyzePayload) -> some View {
        let total = max(payload.entries.reduce(UInt64(0)) { $0 + $1.size }, 1)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Largest in \(payload.path)")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text("\(payload.entries.count) entries · \(ByteFormat.string(total))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(payload.entries.prefix(80)) { entry in
                Button {
                    if entry.isDir {
                        drill(into: entry.path)
                    } else {
                        reveal(entry.path)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: entry.isDir ? "folder.fill" : "doc")
                            .foregroundStyle(entry.isDir ? Color.accentColor : .secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(entry.path)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if entry.cleanable == true {
                            Text("cleanable")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                        Text(entry.sizeLabel)
                            .font(.callout.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 72, alignment: .trailing)
                        if entry.isDir {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Reveal in Finder") { reveal(entry.path) }
                    if entry.isDir {
                        Button("Scan this folder") { drill(into: entry.path) }
                    }
                    Button("Copy path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.path, forType: .string)
                    }
                }

                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor.opacity(0.25))
                        .frame(width: geo.size.width * CGFloat(Double(entry.size) / Double(total)))
                }
                .frame(height: 4)

                Divider()
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: appState.analyzePath)
        if panel.runModal() == .OK, let url = panel.url {
            appState.analyzeStack = []
            Task { await appState.runAnalyze(path: url.path) }
        }
    }

    private func drill(into next: String) {
        Task { await appState.analyzeDrill(into: next) }
    }

    private func reveal(_ target: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: target)])
    }

}
