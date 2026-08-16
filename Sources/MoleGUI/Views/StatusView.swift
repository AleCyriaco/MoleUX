import SwiftUI

struct StatusView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    SectionHeader(
                        title: "Live Status",
                        subtitle: "Metrics from `mo status --json` every \(Int(appState.liveRefreshSeconds))s."
                    )
                    Spacer()
                    if appState.isLoadingStatus {
                        ProgressView().controlSize(.small)
                    }
                }

                if let s = appState.status {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                        MetricCard(title: "Health", value: "\(s.healthScore)", subtitle: s.healthScoreMsg, systemImage: "heart.fill", progress: Double(s.healthScore) / 100, tint: .pink)
                        MetricCard(title: "CPU", value: String(format: "%.1f%%", s.cpu.usage), subtitle: String(format: "L1 %.2f  L5 %.2f", s.cpu.load1, s.cpu.load5), systemImage: "cpu", progress: s.cpu.usage / 100, tint: .blue)
                        MetricCard(title: "Memory", value: String(format: "%.1f%%", s.memory.usedPercent), subtitle: ByteFormat.string(s.memory.available) + " available", systemImage: "memorychip", progress: s.memory.usedPercent / 100, tint: .purple)
                        if let d = s.primaryDisk {
                            MetricCard(title: "Disk", value: String(format: "%.1f%%", d.usedPercent), subtitle: d.mount, systemImage: "internaldrive", progress: d.usedPercent / 100, tint: .orange)
                        }
                        if let b = s.primaryBattery {
                            MetricCard(title: "Battery", value: String(format: "%.0f%%", b.percent), subtitle: "\(b.status) · cycles \(b.cycleCount ?? 0)", systemImage: "battery.75", progress: b.percent / 100, tint: .green)
                        }
                        MetricCard(
                            title: "Power",
                            value: s.thermal.systemPower.map { String(format: "%.1f W", $0) }
                                ?? s.thermal.batteryPower.map { String(format: "%.1f W bat", $0) }
                                ?? "—",
                            subtitle: s.thermal.batteryTemp > 0
                                ? String(format: "Battery temp %.1f°C", s.thermal.batteryTemp)
                                : (s.thermal.cpuTemp > 0 ? String(format: "CPU %.0f°C", s.thermal.cpuTemp) : "Sensors limited"),
                            systemImage: "thermometer.medium",
                            tint: .red
                        )
                        if let gpu = s.gpu.first {
                            MetricCard(
                                title: "GPU",
                                value: gpu.usage >= 0 ? String(format: "%.0f%%", gpu.usage) : gpu.name,
                                subtitle: gpu.usage >= 0
                                    ? "\(gpu.name) · \(gpu.coreCount) cores"
                                    : "\(gpu.coreCount) cores · usage N/A",
                                systemImage: "rectangle.on.rectangle.angled",
                                progress: gpu.usage >= 0 ? gpu.usage / 100 : nil,
                                tint: .mint
                            )
                        }
                    }

                    cpuCores(s.cpu)
                    processes(s.topProcesses)
                    networks(s.network)
                } else {
                    ContentUnavailableView(
                        "Waiting for metrics",
                        systemImage: "heart.text.square",
                        description: Text(appState.moleAvailable ? "Collecting first snapshot…" : "Connect the Mole CLI in Settings.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 280)
                }
            }
            .padding(24)
        }
        .navigationTitle("Live Status")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await appState.refreshStatus() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private func cpuCores(_ cpu: CPUStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Per-core CPU")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                ForEach(Array(cpu.perCore.enumerated()), id: \.offset) { idx, value in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.blue.opacity(0.15))
                            .frame(height: 64)
                            .overlay(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.blue)
                                    .frame(height: max(4, 64 * min(value, 100) / 100))
                            }
                        Text("\(idx)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func processes(_ list: [ProcInfo]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top processes")
                .font(.headline)
            ForEach(list.prefix(10)) { proc in
                HStack {
                    Text(proc.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Spacer()
                    Text(String(format: "%.1f%% CPU", proc.cpu))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f%% MEM", proc.memory))
                        .font(.caption.monospacedDigit())
                        .frame(width: 80, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    Text("pid \(proc.pid)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .frame(width: 70, alignment: .trailing)
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private func networks(_ nets: [NetworkStatus]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Network interfaces")
                .font(.headline)
            ForEach(nets) { net in
                HStack {
                    Image(systemName: "network")
                    Text(net.name).fontWeight(.medium)
                    if let ip = net.ip, !ip.isEmpty {
                        Text(ip).foregroundStyle(.secondary).font(.caption.monospaced())
                    }
                    Spacer()
                    Text(String(format: "↓ %.3f MB/s", net.rxRateMBs))
                        .font(.caption.monospacedDigit())
                    Text(String(format: "↑ %.3f MB/s", net.txRateMBs))
                        .font(.caption.monospacedDigit())
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
}
