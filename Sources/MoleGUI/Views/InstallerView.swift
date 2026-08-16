import AppKit
import SwiftUI

struct InstallerView: View {
    @EnvironmentObject private var appState: AppState
    @State private var confirm = false

    private var files: [InstallerFile] { appState.installerFiles }
    private var busy: Bool { appState.isRunning(.installer) }

    private var selectedFiles: [InstallerFile] {
        files.filter { appState.installerSelection.contains($0.id) }
    }

    private var selectedSize: UInt64 { selectedFiles.reduce(0) { $0 + $1.size } }
    private var totalSize: UInt64 { files.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            table
        }
        .navigationTitle("Installers")
        .task {
            // Only on first visit — a rescan on every tab switch would throw
            // away the selection the user is building.
            if !appState.installerScanned, !busy {
                await appState.scanInstallers()
            }
        }
        .confirmationDialog(
            "Move \(appState.installerSelection.count) installer\(appState.installerSelection.count == 1 ? "" : "s") to Trash?",
            isPresented: $confirm,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                let targets = selectedFiles
                Task { await appState.trashInstallers(targets) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Frees \(ByteFormat.string(selectedSize)). Files go to the macOS Trash and can be put back from Finder.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Installers",
                subtitle: "Leftover .dmg, .pkg, .mpkg, .iso and .xip files in your download folders — the app is already installed, the image is not needed."
            )

            callout

            HStack(spacing: 12) {
                SecondaryActionButton(
                    title: busy ? "Working…" : "Rescan",
                    systemImage: "arrow.clockwise",
                    isLoading: busy
                ) {
                    Task { await appState.scanInstallers() }
                }
                .frame(maxWidth: 170)

                SecondaryActionButton(title: "Select all", systemImage: "checkmark.circle") {
                    appState.installerSelection = Set(files.map(\.id))
                }
                .frame(maxWidth: 150)
                .disabled(files.isEmpty)

                ActionButton(
                    title: appState.installerSelection.isEmpty
                        ? "Move to Trash"
                        : "Move to Trash (\(appState.installerSelection.count))",
                    systemImage: "trash.fill",
                    role: .destructive,
                    isLoading: busy
                ) {
                    confirm = true
                }
                .frame(maxWidth: 230)
                .disabled(appState.installerSelection.isEmpty || busy)

                Spacer()

                Button {
                    appState.openInTerminal(["installer"])
                } label: {
                    Label("Terminal UI", systemImage: "terminal")
                }
                .buttonStyle(.bordered)
                .disabled(!appState.moleAvailable)
                .help("Opens `mo installer`, the CLI's own interactive selector.")
            }

            HStack(spacing: 12) {
                Text("\(files.count) files · \(ByteFormat.string(totalSize))")
                if !appState.installerSelection.isEmpty {
                    Text("· \(appState.installerSelection.count) selected · \(ByteFormat.string(selectedSize))")
                        .foregroundStyle(Color.accentColor)
                }
                if !appState.installerStatus.isEmpty {
                    Text("· \(appState.installerStatus)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var callout: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.title2)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text("Post-install leftovers")
                    .fontWeight(.semibold)
                Text("Scans the same folders as `mo installer` and removes through the Trash, so anything you change your mind about is one Finder click away. Archives (.zip) are left alone.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var table: some View {
        Group {
            if busy && files.isEmpty {
                ProgressView("Scanning download folders…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if files.isEmpty {
                ContentUnavailableView(
                    "No installers found",
                    systemImage: "checkmark.seal",
                    description: Text("Nothing left over in Downloads, Desktop, or the other scan folders.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(files, selection: $appState.installerSelection) {
                    TableColumn("File") { file in
                        HStack(spacing: 10) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                                .resizable()
                                .frame(width: 22, height: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                Text(file.url.deletingLastPathComponent().path)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .width(min: 280, ideal: 380)

                    TableColumn("Size") { file in
                        Text(file.sizeLabel)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .width(80)

                    TableColumn("Where") { file in
                        Text(file.source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .width(90)

                    TableColumn("Modified") { file in
                        Text(file.modified.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .width(110)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                .contextMenu(forSelectionType: String.self) { ids in
                    if let id = ids.first, let file = files.first(where: { $0.id == id }) {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([file.url])
                        }
                    }
                }
            }
        }
    }
}
