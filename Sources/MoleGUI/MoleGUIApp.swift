import SwiftUI

@main
struct MoleGUIApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Mole") {
                Button("Refresh Status") {
                    Task { await appState.refreshStatus() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Divider()

                Button("Open Mole CLI Folder") {
                    appState.revealMoleHome()
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
