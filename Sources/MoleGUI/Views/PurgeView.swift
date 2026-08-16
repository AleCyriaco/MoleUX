import SwiftUI

struct PurgeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var confirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader(
                    title: "Purge",
                    subtitle: "Remove old project build artifacts (node_modules leftovers, target/, DerivedData-style caches under your code folders)."
                )

                callout

                ActivityActions(
                    section: .purge,
                    runTitle: "Run Purge",
                    runIcon: "folder.badge.minus",
                    runRole: .destructive,
                    onPreview: { Task { await appState.runPurge(dryRun: true) } },
                    onRun: { confirm = true }
                )

                ActivityConsole(section: .purge, title: "Purge output")
            }
            .padding(24)
        }
        .navigationTitle("Purge")
        .confirmationDialog("Purge project artifacts?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Run Purge", role: .destructive) {
                Task { await appState.runPurge(dryRun: false) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Mole scans common project directories and removes rebuildable artifacts. Preview with dry-run first.")
        }
    }

    private var callout: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hammer.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Developer build cleanup")
                    .fontWeight(.semibold)
                Text("Targets known artifact patterns under ~/dev, ~/Projects, and similar folders. Source files stay untouched.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}
