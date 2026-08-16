import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                metricsGrid
                quickActions
                recentActivity
            }
            .padding(24)
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await appState.refreshStatus(); await appState.refreshHistory() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(appState.isLoadingStatus)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 24) {
            if let status = appState.status {
                HealthRing(score: status.healthScore, label: status.healthScoreMsg)
                VStack(alignment: .leading, spacing: 8) {
                    Text(status.hardware.model)
                        .font(.largeTitle.weight(.bold))
                    Text("\(status.hardware.cpuModel) · \(status.hardware.totalRAM) · \(status.hardware.osVersion)")
                        .foregroundStyle(.secondary)
                    Text("Uptime \(status.uptime) · \(status.procs) processes · \(status.host)")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            } else {
                ProgressView("Loading system health…")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 40)
            }
            Spacer()
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
            if let s = appState.status {
                MetricCard(
                    title: "CPU",
                    value: String(format: "%.0f%%", s.cpu.usage),
                    subtitle: String(format: "Load %.2f · %d cores", s.cpu.load1, s.cpu.coreCount),
                    systemImage: "cpu",
                    progress: s.cpu.usage / 100,
                    tint: .blue
                )
                MetricCard(
                    title: "Memory",
                    value: String(format: "%.0f%%", s.memory.usedPercent),
                    subtitle: "\(ByteFormat.string(s.memory.used)) of \(ByteFormat.string(s.memory.total))",
                    systemImage: "memorychip",
                    progress: s.memory.usedPercent / 100,
                    tint: .purple
                )
                if let disk = s.primaryDisk {
                    MetricCard(
                        title: "Disk",
                        value: String(format: "%.0f%%", disk.usedPercent),
                        subtitle: "\(ByteFormat.string(disk.freeBytes)) free of \(ByteFormat.string(disk.total))",
                        systemImage: "internaldrive",
                        progress: disk.usedPercent / 100,
                        tint: disk.usedPercent > 90 ? .red : .orange
                    )
                }
                if let bat = s.primaryBattery {
                    MetricCard(
                        title: "Battery",
                        value: String(format: "%.0f%%", bat.percent),
                        subtitle: "\(bat.status.capitalized)\(bat.timeLeft.map { " · \($0)" } ?? "")",
                        systemImage: "battery.100",
                        progress: bat.percent / 100,
                        tint: .green
                    )
                }
                MetricCard(
                    title: "Trash",
                    value: ByteFormat.string(s.trashSize),
                    subtitle: s.trashApprox ? "Approximate size" : "Ready to empty via Clean",
                    systemImage: "trash",
                    tint: .gray
                )
                if let net = s.network.first(where: { !($0.ip ?? "").isEmpty }) ?? s.network.first {
                    MetricCard(
                        title: "Network",
                        value: net.name,
                        subtitle: String(format: "↓ %.2f  ↑ %.2f MB/s", net.rxRateMBs, net.txRateMBs),
                        systemImage: "network",
                        tint: .cyan
                    )
                }
            }
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Quick actions", subtitle: "Safe defaults — destructive work always starts with a preview.")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                quickCard("Preview Clean", "trash", .clean)
                quickCard("Optimize", "bolt.circle", .optimize)
                quickCard("Uninstall Apps", "app.badge.checkmark", .uninstall)
                quickCard("Purge Artifacts", "folder.badge.minus", .purge)
                quickCard("Installers", "shippingbox", .installer)
                quickCard("Live Status", "heart.text.square", .status)
                quickCard("Disk Analyze", "chart.pie", .analyze)
                quickCard("History", "clock", .history)
            }
        }
    }

    private func quickCard(_ title: String, _ icon: String, _ section: AppState.Section) -> some View {
        Button {
            appState.section = section
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 28)
                Text(title)
                    .fontWeight(.medium)
                Spacer()
                if appState.isRunning(section) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                        .frame(width: 14, height: 14)
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.06))
            }
        }
        .buttonStyle(.plain)
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Recent activity")
            if let sessions = appState.history?.sessions, !sessions.isEmpty {
                ForEach(sessions.prefix(5)) { session in
                    HStack {
                        Image(systemName: icon(for: session.command))
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.command.capitalized)
                                .fontWeight(.medium)
                            Text(session.startedAt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(session.size ?? "—")
                                .fontWeight(.semibold)
                            Text("\(session.items ?? 0) items")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                }
            } else {
                Text("No cleanup sessions yet. Run Clean or Uninstall to start a history.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
    }

    private func icon(for command: String) -> String {
        switch command.lowercased() {
        case "clean": return "trash"
        case "uninstall": return "app.badge.checkmark"
        case "optimize": return "bolt"
        case "purge": return "folder.badge.minus"
        case "installer": return "shippingbox"
        default: return "checkmark.circle"
        }
    }
}
