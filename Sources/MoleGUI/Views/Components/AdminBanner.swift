import SwiftUI

/// Inline strip shown above destructive actions: says whether root-only steps
/// will run, and offers the two ways to make them run.
struct AdminBanner: View {
    @EnvironmentObject private var appState: AppState
    /// Command handed to Terminal when the user chooses the native prompt.
    let terminalCommand: [String]

    private var state: AdminAccess.State { appState.adminState }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 6) {
                Text(state.canElevate ? "Administrator access ready" : "Administrator access needed")
                    .fontWeight(.semibold)
                Text(state.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if !state.canElevate {
                    Text("A window app has no terminal, so sudo cannot ask for a password. Touch ID authenticates without one.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    HStack(spacing: 10) {
                        Button("Set up Touch ID for sudo") {
                            appState.enableTouchID()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button("Run in Terminal instead") {
                            appState.openInTerminal(terminalCommand)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Re-check") {
                            Task { await appState.refreshAdminState() }
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                    .padding(.top, 2)
                }
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .task { await appState.refreshAdminState() }
    }

    private var icon: String {
        switch state {
        case .touchID: return "touchid"
        case .cached: return "lock.open.fill"
        case .unavailable: return "lock.fill"
        }
    }

    private var tint: Color {
        state.canElevate ? .green : .orange
    }
}

/// First-launch explainer. Same choices as the banner, with room to say why.
struct AdminPromptSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "touchid")
                    .font(.system(size: 34))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Some cleanup needs administrator access")
                        .font(.title3.weight(.semibold))
                    Text("Everything else works without it.")
                        .foregroundStyle(.secondary)
                }
            }

            Text("""
            System caches and a few maintenance tasks belong to root. Mole in the \
            Terminal asks for your password; a window app has no terminal to ask \
            from, so those steps are skipped instead.

            Touch ID for sudo fixes this — it authenticates with the system's own \
            biometric prompt, no terminal and no password dialog involved. Setup \
            runs Mole's own `mo touchid` in Terminal, which needs one admin \
            confirmation.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Not now") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Set up Touch ID") {
                    appState.enableTouchID()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 520)
    }
}
