import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            if let error = appState.lastError {
                errorBanner(error)
            }
        }
        .sheet(isPresented: $appState.showAdminPrompt) {
            AdminPromptSheet()
                .environmentObject(appState)
        }
    }

    private var sidebar: some View {
        List(selection: $appState.section) {
            Section("MoleUX") {
                ForEach(AppState.Section.allCases.filter { $0 != .settings }) { section in
                    Label {
                        HStack(spacing: 6) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(section.rawValue)
                                Text(appState.isRunning(section)
                                     ? appState.activity(section).label
                                     : section.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            // Spinner marks the tab whose work is still running,
                            // so leaving it never hides that something is going on.
                            if appState.isRunning(section) {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.7)
                                    .frame(width: 14, height: 14)
                            }
                        }
                    } icon: {
                        Image(systemName: section.systemImage)
                    }
                    .tag(section)
                }
            }

            Section {
                Label(AppState.Section.settings.rawValue, systemImage: AppState.Section.settings.systemImage)
                    .tag(AppState.Section.settings)
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(appState.moleAvailable ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(appState.moleAvailable ? "CLI connected" : "CLI missing")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("v\(appState.moleVersion)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                    if let score = appState.status?.healthScore {
                        Text("Health \(score) · \(appState.status?.healthScoreMsg ?? "")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("MoleUX")
    }

    @ViewBuilder
    private var detail: some View {
        switch appState.section {
        case .dashboard:
            DashboardView()
        case .clean:
            CleanView()
        case .uninstall:
            UninstallView()
        case .optimize:
            OptimizeView()
        case .purge:
            PurgeView()
        case .installer:
            InstallerView()
        case .analyze:
            AnalyzeView()
        case .status:
            StatusView()
        case .history:
            HistoryView()
        case .settings:
            SettingsView()
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.callout)
                .lineLimit(2)
            Spacer()
            Button("Dismiss") { appState.lastError = nil }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding()
    }
}
