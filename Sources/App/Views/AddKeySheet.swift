import SwiftUI

struct AddKeySheet: View {
    let onSave: (CaptureDraft) throws -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedProviderSlug = ""
    @State private var customProviderName = ""
    @State private var keyName = ""
    @State private var apiKey = ""
    @State private var environmentPreset: EnvironmentPreset = .production
    @State private var customEnvironmentName = ""
    @State private var platformURL = ""
    @State private var sourceURL = ""
    @State private var pageTitle = ""
    @State private var notes = ""
    @State private var errorMessage: String?

    private var effectiveEnvironment: String {
        environmentPreset == .custom ? customEnvironmentName : environmentPreset.rawValue
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

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Add Key")
                        .font(.system(size: 28, weight: .bold))

                    GlassField(title: "Provider") {
                        Picker("Provider", selection: $selectedProviderSlug) {
                            Text("Custom").tag("")
                            ForEach(ProviderCatalog.supportedProviders) { provider in
                                Text(provider.displayName).tag(provider.slug)
                            }
                        }
                        .pickerStyle(.menu)
                        .glassInputShell()
                    }

                    if selectedProviderSlug.isEmpty {
                        GlassField(title: "Custom Provider") {
                            TextField("Example: Alchemy", text: $customProviderName)
                                .textFieldStyle(.plain)
                                .glassInputShell()
                        }
                    }

                    GlassField(title: "API Key") {
                        TextEditor(text: $apiKey)
                            .frame(minHeight: 110)
                            .scrollContentBackground(.hidden)
                            .glassInputShell()
                    }

                    GlassField(title: "Key Name") {
                        TextField("Example: ANTHROPIC_API_KEY", text: $keyName)
                            .textFieldStyle(.plain)
                            .glassInputShell()
                    }

                    GlassField(title: "Environment") {
                        Picker("Environment", selection: $environmentPreset) {
                            ForEach(EnvironmentPreset.allCases) { preset in
                                Text(preset.label).tag(preset)
                            }
                        }
                        .pickerStyle(.menu)
                        .glassInputShell()
                    }

                    if environmentPreset == .custom {
                        GlassField(title: "Custom Environment") {
                            TextField("Example: sandbox", text: $customEnvironmentName)
                                .textFieldStyle(.plain)
                                .glassInputShell()
                        }
                    }

                    GlassField(title: "Platform Link") {
                        TextField("https://api.example.com", text: $platformURL)
                            .textFieldStyle(.plain)
                            .glassInputShell()
                    }

                    GlassField(title: "Source URL") {
                        TextField("https://example.com", text: $sourceURL)
                            .textFieldStyle(.plain)
                            .glassInputShell()
                    }

                    GlassField(title: "Page Title") {
                        TextField("Settings - Example", text: $pageTitle)
                            .textFieldStyle(.plain)
                            .glassInputShell()
                    }

                    GlassField(title: "Notes") {
                        TextEditor(text: $notes)
                            .frame(minHeight: 96)
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
        }
        .frame(width: 540, height: 720)
    }

    private func save() {
        do {
            let draft = CaptureDraft(
                providerSlug: selectedProviderSlug.isEmpty ? nil : selectedProviderSlug,
                providerDisplayName: selectedProviderSlug.isEmpty ? customProviderName : ProviderCatalog.provider(for: selectedProviderSlug)?.displayName,
                keyName: keyName,
                apiKey: apiKey,
                platformURL: platformURL,
                sourceURL: sourceURL,
                pageTitle: pageTitle,
                notes: notes,
                environment: effectiveEnvironment,
                capturedAt: Date()
            )
            try onSave(draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
