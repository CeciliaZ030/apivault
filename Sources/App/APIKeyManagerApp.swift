import SwiftUI

@main
struct APIKeyManagerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .modelContainer(appState.modelContainer)
                .task {
                    appState.startBridgeIfNeeded()
                }
        }
        .defaultSize(width: 1040, height: 680)

        Settings {
            InstructionsView()
                .environmentObject(appState)
                .modelContainer(appState.modelContainer)
                .frame(width: 520, height: 420)
        }
    }
}
