import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var pathDraft: String = ""
    @State private var refreshDraft: Double = 5

    var body: some View {
        Form {
            Section("Mole CLI") {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(appState.moleAvailable ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(appState.moleAvailable ? "Connected" : "Not found")
                    }
                }
                LabeledContent("Version") {
                    Text(appState.moleVersion).font(.body.monospaced())
                }
                TextField("Path to mo / mole", text: $pathDraft)
                    .textFieldStyle(.roundedBorder)
                    .onAppear {
                        pathDraft = appState.molePath
                        refreshDraft = appState.liveRefreshSeconds
                    }
                HStack {
                    Button("Browse…") { browse() }
                    Button("Apply") {
                        appState.updateMolePath(pathDraft)
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("Auto-detect") {
                        pathDraft = ""
                        appState.updateMolePath("")
                        pathDraft = appState.molePath
                    }
                }
                if !appState.molePath.isEmpty {
                    Text(appState.molePath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Administrator access") {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(appState.adminState.canElevate ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(appState.adminState == .touchID ? "Touch ID for sudo"
                             : appState.adminState == .cached ? "Session credential cached"
                             : "Not available")
                    }
                }
                Text(appState.adminState.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Set up Touch ID for sudo") { appState.enableTouchID() }
                        .disabled(appState.adminState == .touchID)
                    Button("Re-check") {
                        Task { await appState.refreshAdminState() }
                    }
                }
            }

            Section("Live status") {
                HStack {
                    Text("Refresh interval")
                    Spacer()
                    Text("\(Int(refreshDraft))s")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $refreshDraft, in: 2...30, step: 1) {
                    Text("Refresh interval")
                } minimumValueLabel: {
                    Text("2s")
                } maximumValueLabel: {
                    Text("30s")
                }
                .onChange(of: refreshDraft) { _, newValue in
                    appState.startLiveStatus(interval: newValue)
                }
                Button("Refresh now") {
                    Task { await appState.refreshStatus() }
                }
            }

            Section("About") {
                Text("Mole GUI is a native SwiftUI front-end for the open-source Mole CLI. Destructive actions stay previewable and route through the same safety helpers as the terminal tool.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Link("mole.fit", destination: URL(string: "https://mole.fit")!)
                Link("GitHub tw93/mole", destination: URL(string: "https://github.com/tw93/mole")!)
            }

            Section("Development") {
                Text("This app lives under gui/mac and shells out to the CLI. Bundle the CLI next to the app or point Settings at your checkout’s ./mole binary.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 480, minHeight: 420)
        .navigationTitle("Settings")
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        if panel.runModal() == .OK, let url = panel.url {
            pathDraft = url.path
            appState.updateMolePath(pathDraft)
        }
    }
}
