import SwiftUI

struct OptimizeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var confirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader(
                    title: "Optimize",
                    subtitle: "Refresh system caches and services. Prefer dry-run first — some steps may request elevated privileges."
                )

                callout

                AdminBanner(terminalCommand: ["optimize"])

                ActivityActions(
                    section: .optimize,
                    runTitle: "Run Optimize",
                    runIcon: "bolt.circle.fill",
                    onPreview: { Task { await appState.runOptimize(dryRun: true) } },
                    onRun: { confirm = true }
                )

                ActivityConsole(section: .optimize, title: "Optimize output")
            }
            .padding(24)
        }
        .navigationTitle("Optimize")
        .confirmationDialog("Run system optimize?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Run Optimize") {
                Task { await appState.runOptimize(dryRun: false) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Mole will refresh caches and services. Some steps may need admin rights and can briefly affect running apps.")
        }
    }

    private var callout: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bolt.shield.fill")
                .font(.title2)
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 4) {
                Text("Maintenance pass")
                    .fontWeight(.semibold)
                Text("Rebuilds indexes, flushes stale caches, and restarts helper services. Not a substitute for Clean when you need free disk space.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}
