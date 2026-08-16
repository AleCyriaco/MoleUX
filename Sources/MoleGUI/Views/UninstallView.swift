import AppKit
import SwiftUI

struct UninstallView: View {
    @EnvironmentObject private var appState: AppState
    @State private var confirmUninstall = false

    // Selection, filter, and output live in AppState so a running uninstall and
    // a half-built selection both survive a tab switch.
    private var selection: Set<String> { appState.uninstallSelection }
    private var permanent: Bool { appState.uninstallPermanent }
    private var busy: Bool { appState.isRunning(.uninstall) }

    private var filtered: [InstalledApp] {
        let q = appState.uninstallQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = appState.installedApps
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || $0.uninstallName.localizedCaseInsensitiveContains(q)
                || ($0.bundleId?.localizedCaseInsensitiveContains(q) ?? false)
                || $0.path.localizedCaseInsensitiveContains(q)
        }
    }

    private var selectedApps: [InstalledApp] {
        appState.installedApps.filter { selection.contains($0.id) }
    }

    private func uninstall(dryRun: Bool) {
        let names = selectedApps.map(\.uninstallName)
        guard !names.isEmpty else { return }
        let wasPermanent = permanent && !dryRun
        Task {
            await appState.runUninstall(apps: names, dryRun: dryRun, permanent: wasPermanent)
            if !dryRun, appState.activity(.uninstall).succeeded == true {
                appState.uninstallSelection.removeAll()
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .navigationTitle("Uninstall")
        .task {
            if appState.installedApps.isEmpty {
                await appState.refreshInstalledApps()
            }
        }
        .confirmationDialog(
            permanent ? "Permanently uninstall selected apps?" : "Move selected apps to Trash?",
            isPresented: $confirmUninstall,
            titleVisibility: .visible
        ) {
            Button(permanent ? "Uninstall permanently" : "Uninstall", role: .destructive) {
                uninstall(dryRun: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let names = selectedApps.map(\.name).joined(separator: ", ")
            Text(permanent
                 ? "\(names) will be removed immediately (no Trash). This cannot be undone from Finder."
                 : "\(names) and known leftovers will go to the macOS Trash when possible.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Uninstall",
                subtitle: "Select apps to remove completely — binaries plus known leftovers. Always preview first."
            )

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter by name, bundle id, or path", text: $appState.uninstallQuery)
                    .textFieldStyle(.plain)
                if !appState.uninstallQuery.isEmpty {
                    Button {
                        appState.uninstallQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 12) {
                SecondaryActionButton(
                    title: appState.isLoadingApps ? "Loading…" : "Refresh list",
                    systemImage: "arrow.clockwise",
                    isLoading: appState.isLoadingApps
                ) {
                    Task { await appState.refreshInstalledApps() }
                }
                .frame(maxWidth: 180)

                SecondaryActionButton(
                    title: "Preview selected",
                    systemImage: "eye",
                    isLoading: busy && appState.activity(.uninstall).isDryRun
                ) {
                    uninstall(dryRun: true)
                }
                .disabled(selection.isEmpty || busy)
                .frame(maxWidth: 180)

                ActionButton(
                    title: selection.isEmpty ? "Uninstall" : "Uninstall (\(selection.count))",
                    systemImage: "trash.fill",
                    role: .destructive,
                    isLoading: busy && !appState.activity(.uninstall).isDryRun
                ) {
                    confirmUninstall = true
                }
                .disabled(selection.isEmpty || busy || !appState.moleAvailable)
                .frame(maxWidth: 200)

                Toggle("Permanent (skip Trash)", isOn: $appState.uninstallPermanent)
                    .toggleStyle(.checkbox)
                    .help("Bypasses macOS Trash and removes immediately.")

                Spacer()

                Button {
                    appState.openInTerminal(["uninstall"])
                } label: {
                    Label("Terminal UI", systemImage: "terminal")
                }
                .buttonStyle(.bordered)
            }

            Text("\(filtered.count) apps · \(selection.count) selected")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var content: some View {
        HSplitView {
            appTable
                .frame(minWidth: 420)

            VStack(alignment: .leading, spacing: 12) {
                if let first = selectedApps.first {
                    selectionDetail(first)
                } else {
                    ContentUnavailableView(
                        "Select an app",
                        systemImage: "app.badge.checkmark",
                        description: Text("Choose one or more apps, preview leftovers, then uninstall.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                ActivityConsole(section: .uninstall, title: "Uninstall output")
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
            .frame(minWidth: 320)
        }
    }

    private var appTable: some View {
        Group {
            if appState.isLoadingApps && appState.installedApps.isEmpty {
                ProgressView("Loading installed apps…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                ContentUnavailableView(
                    appState.uninstallQuery.isEmpty ? "No apps found" : "No matches",
                    systemImage: "app.dashed",
                    description: Text(appState.uninstallQuery.isEmpty
                                      ? "Refresh the list or check the Mole CLI path in Settings."
                                      : "Try a different filter.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(filtered, selection: $appState.uninstallSelection) {
                    TableColumn("App") { app in
                        HStack(spacing: 10) {
                            appIcon(for: app)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                Text(app.path)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .width(min: 220, ideal: 280)

                    TableColumn("Size") { app in
                        Text(app.displaySize)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .width(70)

                    TableColumn("Source") { app in
                        Text(app.sourceLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .width(70)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                .onTapGesture(count: 2) {}
            }
        }
    }

    private func selectionDetail(_ app: InstalledApp) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                appIcon(for: app, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name)
                        .font(.title3.weight(.semibold))
                    if let bid = app.bundleId, !bid.isEmpty, bid != "unknown" {
                        Text(bid)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                Spacer()
            }

            LabeledContent("Uninstall name") {
                Text(app.uninstallName).font(.body.monospaced())
            }
            LabeledContent("Path") {
                Text(app.path)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
            LabeledContent("Size") {
                Text(app.displaySize)
            }

            if selection.count > 1 {
                Text("+\(selection.count - 1) more selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .padding([.horizontal, .top], 16)
    }

    private func appIcon(for app: InstalledApp, size: CGFloat = 28) -> some View {
        let image = NSWorkspace.shared.icon(forFile: app.path)
        return Image(nsImage: image)
            .resizable()
            .frame(width: size, height: size)
            .cornerRadius(6)
    }

}
