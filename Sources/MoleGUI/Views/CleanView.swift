import SwiftUI

struct CleanView: View {
    @EnvironmentObject private var appState: AppState
    @State private var confirmClean = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader(
                    title: "Clean",
                    subtitle: "Free rebuildable caches and leftovers. Always preview first — Mole routes deletions through Trash when possible."
                )

                safetyCallout

                AdminBanner(terminalCommand: ["clean"])

                ActivityActions(
                    section: .clean,
                    runTitle: "Run Clean",
                    runIcon: "trash.fill",
                    runRole: .destructive,
                    onPreview: { Task { await appState.runClean(dryRun: true) } },
                    onRun: { confirmClean = true }
                )

                if let disk = appState.status?.primaryDisk {
                    MetricCard(
                        title: "Disk pressure",
                        value: String(format: "%.1f%% used", disk.usedPercent),
                        subtitle: "\(ByteFormat.string(disk.freeBytes)) free · purgeable targets appear in dry-run",
                        systemImage: "internaldrive.fill",
                        progress: disk.usedPercent / 100,
                        tint: disk.usedPercent > 85 ? .red : .orange
                    )
                }

                ActivityConsole(section: .clean, title: "Clean output")
            }
            .padding(24)
        }
        .navigationTitle("Clean")
        .confirmationDialog(
            "Run system clean?",
            isPresented: $confirmClean,
            titleVisibility: .visible
        ) {
            Button("Run Clean", role: .destructive) {
                Task { await appState.runClean(dryRun: false) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Mole will remove known-safe caches and leftovers. Review the dry-run preview first when possible. Some items go to Trash.")
        }
    }

    private var safetyCallout: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shield.checkered")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 4) {
                Text("Safety-first cleanup")
                    .fontWeight(.semibold)
                Text("Uses the same path protection and dry-run contract as the CLI. Documents, credentials, and active developer state stay protected.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}
