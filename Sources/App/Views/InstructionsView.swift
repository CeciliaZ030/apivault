import SwiftUI

struct InstructionsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Apivault")
                .font(.title2)
                .fontWeight(.semibold)

            GroupBox("Bridge Status") {
                Text(appState.bridgeStatusMessage ?? "Bridge has not started yet.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.secondary)
            }

            GroupBox("Manual Logging") {
                Text("Use the Safari extension to log keys and usage manually. Current page URL is attached automatically, and saved keys remain encrypted in the local Keychain.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
