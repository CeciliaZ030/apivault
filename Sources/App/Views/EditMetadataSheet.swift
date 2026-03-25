import SwiftUI

struct EditMetadataSheet: View {
    let item: VaultItemRecord
    let onSave: (String, String, String, String, String, String, String) throws -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var providerDisplayName: String
    @State private var environment: String
    @State private var keyName: String
    @State private var platformURL: String
    @State private var sourceURL: String
    @State private var pageTitle: String
    @State private var notes: String
    @State private var errorMessage: String?

    init(item: VaultItemRecord, onSave: @escaping (String, String, String, String, String, String, String) throws -> Void) {
        self.item = item
        self.onSave = onSave
        _providerDisplayName = State(initialValue: item.providerDisplayName)
        _environment = State(initialValue: item.environmentName)
        _keyName = State(initialValue: item.keyName ?? "")
        _platformURL = State(initialValue: item.platformURL ?? "")
        _sourceURL = State(initialValue: item.sourceURL)
        _pageTitle = State(initialValue: item.pageTitle ?? "")
        _notes = State(initialValue: item.notes ?? "")
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.87, green: 0.92, blue: 0.97),
                    Color(red: 0.73, green: 0.79, blue: 0.89)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Text("Edit Metadata")
                    .font(.system(size: 28, weight: .bold))

                GlassField(title: "Provider Name") {
                    TextField("Provider Name", text: $providerDisplayName)
                        .textFieldStyle(.plain)
                        .glassInputShell()
                }

                GlassField(title: "Environment") {
                    TextField("Environment", text: $environment)
                        .textFieldStyle(.plain)
                        .glassInputShell()
                }

                GlassField(title: "Key Name") {
                    TextField("Key Name", text: $keyName)
                        .textFieldStyle(.plain)
                        .glassInputShell()
                }

                GlassField(title: "Platform Link") {
                    TextField("Platform Link", text: $platformURL)
                        .textFieldStyle(.plain)
                        .glassInputShell()
                }

                GlassField(title: "Source URL") {
                    TextField("Source URL", text: $sourceURL)
                        .textFieldStyle(.plain)
                        .glassInputShell()
                }

                GlassField(title: "Page Title") {
                    TextField("Page Title", text: $pageTitle)
                        .textFieldStyle(.plain)
                        .glassInputShell()
                }

                GlassField(title: "Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 110)
                        .scrollContentBackground(.hidden)
                        .glassInputShell()
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.red)
                }

                HStack {
                    Spacer()

                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(DashboardActionButtonStyle())

                    Button("Save") {
                        save()
                    }
                    .buttonStyle(DashboardActionButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(22)
            .glassPanel(cornerRadius: 28, tintOpacity: 0.10)
            .padding(24)
        }
        .frame(width: 540, height: 640)
    }

    private func save() {
        do {
            try onSave(providerDisplayName, environment, keyName, platformURL, sourceURL, pageTitle, notes)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
