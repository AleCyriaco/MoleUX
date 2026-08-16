import SwiftUI

/// Output pane backed by `AppState.activities`, not by view state — the run
/// keeps going and keeps filling this when the user is looking at another tab.
struct ActivityConsole: View {
    @EnvironmentObject private var appState: AppState
    let section: AppState.Section
    var title: String = "Output"

    private var activity: Activity { appState.activity(section) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if activity.isRunning {
                    ProgressView().controlSize(.small)
                    Text(activity.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let elapsed = activity.durationLabel {
                        Text("· \(elapsed)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                } else if let succeeded = activity.succeeded {
                    Image(systemName: succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(succeeded ? .green : .orange)
                    Text(resultLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if activity.isRunning {
                    Button(role: .destructive) {
                        appState.cancel(section)
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                } else if activity.hasResult {
                    Button("Clear") { appState.clearOutput(section) }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(activity.output.isEmpty ? "No output yet." : activity.output)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    // Anchor the auto-scroll to the end of the stream.
                    Color.clear.frame(height: 1).id(Self.bottomID)
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 320)
                .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(Color.green.opacity(0.9))
                .onChange(of: activity.output) { _, _ in
                    guard activity.isRunning else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(Self.bottomID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private static let bottomID = "activity-console-bottom"

    private var resultLabel: String {
        let verb = activity.exitCode == 130 ? "Cancelled" : (activity.succeeded == true ? "Finished" : "Failed")
        guard let elapsed = activity.durationLabel else { return verb }
        return "\(verb) in \(elapsed)"
    }
}

/// The pair of buttons every command section shows. Disabled while that
/// section is busy; other sections stay clickable and run alongside.
struct ActivityActions: View {
    @EnvironmentObject private var appState: AppState
    let section: AppState.Section
    let runTitle: String
    var runIcon: String
    var runRole: ButtonRole? = nil
    let onPreview: () -> Void
    let onRun: () -> Void

    private var busy: Bool { appState.isRunning(section) }

    var body: some View {
        HStack(spacing: 12) {
            SecondaryActionButton(
                title: "Preview (dry-run)",
                systemImage: "eye",
                isLoading: busy && appState.activity(section).isDryRun
            ) {
                onPreview()
            }
            .disabled(busy || !appState.moleAvailable)

            ActionButton(
                title: runTitle,
                systemImage: runIcon,
                role: runRole,
                isLoading: busy && !appState.activity(section).isDryRun
            ) {
                onRun()
            }
            .disabled(busy || !appState.moleAvailable)
        }
    }
}
