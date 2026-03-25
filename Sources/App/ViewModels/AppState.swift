import AppKit
import Foundation
import SwiftData
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    let modelContainer: ModelContainer
    let unlockManager = UnlockManager()

    @Published var bridgeStatusMessage: String?
    @Published var lastTransientMessage: String?

    private let keychainService = KeychainService()
    private lazy var vaultService = VaultService(
        modelContext: modelContainer.mainContext,
        keychainService: keychainService,
        unlockManager: unlockManager
    )
    private lazy var bridgeServer = LocalBridgeServer { [weak self] request in
        await MainActor.run {
            guard let self else {
                return BridgeResponseEnvelope(
                    id: request.id,
                    ok: false,
                    code: .internalError,
                    message: "App state is unavailable.",
                    data: nil
                )
            }
            return self.handleBridgeRequest(request)
        }
    }
    private var hasStartedBridge = false

    init() {
        do {
            let schema = Schema([VaultItemRecord.self, UsageLogRecord.self])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
            startBridgeIfNeeded()
        } catch {
            fatalError("Failed to create model container: \(error.localizedDescription)")
        }
    }

    func startBridgeIfNeeded() {
        guard !hasStartedBridge else { return }
        hasStartedBridge = true

        do {
            try bridgeServer.start()
            bridgeStatusMessage = "Bridge listening on localhost:\(AppConstants.bridgePort)."
        } catch {
            bridgeStatusMessage = "Bridge failed to start: \(error.localizedDescription)"
        }
    }

    func lockVault() {
        unlockManager.lock()
        showTransientMessage("Vault locked.")
    }

    func unlockVault() async {
        do {
            try await unlockManager.unlock()
            showTransientMessage("Vault unlocked for this session.")
        } catch {
            showTransientMessage(error.localizedDescription)
        }
    }

    func saveManualDraft(_ draft: CaptureDraft) throws {
        let record = try vaultService.saveDraft(draft)
        showTransientMessage("Saved \(record.providerDisplayName) key.")
    }

    func saveUsageLog(_ draft: UsageLogDraft) throws {
        let record = try vaultService.saveUsageLog(draft)
        showTransientMessage("Logged usage for \(record.sourceProviderDisplayName).")
    }

    func delete(_ item: VaultItemRecord) throws {
        try vaultService.delete(item)
        showTransientMessage("Deleted \(item.providerDisplayName).")
    }

    func revealSecret(for item: VaultItemRecord) throws -> String {
        try vaultService.revealSecret(for: item)
    }

    func copySecret(for item: VaultItemRecord) throws {
        try vaultService.copySecret(for: item)
        showTransientMessage("Copied \(item.providerDisplayName) key.")
    }

    func copyAssignment(for item: VaultItemRecord) throws {
        try vaultService.copyAssignment(for: item)
        let label = item.keyName?.isEmpty == false ? item.keyName! : item.providerDisplayName
        showTransientMessage("Copied \(label)=…")
    }

    func updateMetadata(
        for item: VaultItemRecord,
        providerDisplayName: String,
        environment: String,
        keyName: String,
        platformURL: String,
        sourceURL: String,
        pageTitle: String,
        notes: String
    ) throws {
        try vaultService.updateMetadata(
            for: item,
            providerDisplayName: providerDisplayName,
            environment: environment,
            keyName: keyName,
            platformURL: platformURL,
            sourceURL: sourceURL,
            pageTitle: pageTitle,
            notes: notes
        )
        showTransientMessage("Updated metadata for \(item.providerDisplayName).")
    }

    func exportMetadata() throws {
        let panel = NSSavePanel()
        panel.title = "Export Metadata"
        panel.nameFieldStringValue = "api-key-metadata.json"
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        let data = try vaultService.exportMetadata()
        try data.write(to: url, options: .atomic)
        showTransientMessage("Exported metadata.")
    }

    func activateApp() {
        NSApp.activate(ignoringOtherApps: true)
    }

    func postMessage(_ message: String) {
        showTransientMessage(message)
    }

    func recognizedProvider(for urlString: String?) -> RecognizedProviderMatch? {
        ProviderCatalog.recognize(urlString: urlString)
    }

    func savedPlatforms() -> [SavedPlatformOption] {
        let descriptor = FetchDescriptor<VaultItemRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        let records = (try? modelContainer.mainContext.fetch(descriptor)) ?? []

        return Dictionary(grouping: records, by: \.providerIdentity)
            .map { identity, grouped in
                let environments = Dictionary(
                    grouping: grouped.map { EnvironmentPreset.canonicalName(for: $0.environmentName) },
                    by: { $0.lowercased() }
                )
                .compactMap(\.value.first)
                .sorted()

                return SavedPlatformOption(
                    identity: identity,
                    displayName: grouped.first?.providerDisplayName ?? "Unknown",
                    environments: environments
                )
            }
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    private func handleBridgeRequest(_ request: BridgeEnvelope) -> BridgeResponseEnvelope {
        switch request.type {
        case .ping:
            return BridgeResponseEnvelope(
                id: request.id,
                ok: true,
                code: nil,
                message: "App bridge is reachable.",
                data: BridgeResponseData(
                    appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                    recognizedProvider: nil,
                    unlockState: unlockManager.unlockState,
                    savedItemID: nil,
                    savedUsageLogID: nil,
                    savedPlatforms: savedPlatforms()
                )
            )

        case .requestStatus:
            return BridgeResponseEnvelope(
                id: request.id,
                ok: true,
                code: nil,
                message: nil,
                data: BridgeResponseData(
                    appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                    recognizedProvider: nil,
                    unlockState: unlockManager.unlockState,
                    savedItemID: nil,
                    savedUsageLogID: nil,
                    savedPlatforms: savedPlatforms()
                )
            )

        case .openApp:
            activateApp()
            return BridgeResponseEnvelope(
                id: request.id,
                ok: true,
                code: nil,
                message: "Dashboard is open.",
                data: BridgeResponseData(
                    appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                    recognizedProvider: nil,
                    unlockState: unlockManager.unlockState,
                    savedItemID: nil,
                    savedUsageLogID: nil,
                    savedPlatforms: savedPlatforms()
                )
            )

        case .lockVault:
            lockVault()
            return BridgeResponseEnvelope(
                id: request.id,
                ok: true,
                code: nil,
                message: "Vault locked.",
                data: BridgeResponseData(
                    appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                    recognizedProvider: nil,
                    unlockState: unlockManager.unlockState,
                    savedItemID: nil,
                    savedUsageLogID: nil,
                    savedPlatforms: savedPlatforms()
                )
            )

        case .saveDraft:
            guard let draft = request.payload?.draft else {
                return BridgeResponseEnvelope(
                    id: request.id,
                    ok: false,
                    code: .validationError,
                    message: "Save request is missing its draft payload.",
                    data: nil
                )
            }

            do {
                let record = try vaultService.saveDraft(draft)
                showTransientMessage("Saved \(record.providerDisplayName) key from Safari.")
                activateApp()
                return BridgeResponseEnvelope(
                    id: request.id,
                    ok: true,
                    code: nil,
                    message: "Saved \(record.providerDisplayName) key.",
                    data: BridgeResponseData(
                        appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                        recognizedProvider: nil,
                        unlockState: unlockManager.unlockState,
                        savedItemID: record.id.uuidString,
                        savedUsageLogID: nil,
                        savedPlatforms: savedPlatforms()
                    )
                )
            } catch let error as VaultError {
                let code: BridgeErrorCode = switch error {
                case .locked:
                    .vaultLocked
                case .validation, .duplicate:
                    .validationError
                case .notFound:
                    .notFound
                }
                return BridgeResponseEnvelope(
                    id: request.id,
                    ok: false,
                    code: code,
                    message: error.localizedDescription,
                    data: nil
                )
            } catch {
                return BridgeResponseEnvelope(
                    id: request.id,
                    ok: false,
                    code: .internalError,
                    message: error.localizedDescription,
                    data: nil
                )
            }

        case .saveUsageLog:
            guard let draft = request.payload?.usageLogDraft else {
                return BridgeResponseEnvelope(
                    id: request.id,
                    ok: false,
                    code: .validationError,
                    message: "Usage log request is missing its payload.",
                    data: nil
                )
            }

            do {
                let record = try vaultService.saveUsageLog(draft)
                showTransientMessage("Logged usage for \(record.sourceProviderDisplayName).")
                return BridgeResponseEnvelope(
                    id: request.id,
                    ok: true,
                    code: nil,
                    message: "Logged usage for \(record.sourceProviderDisplayName).",
                    data: BridgeResponseData(
                        appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                        recognizedProvider: nil,
                        unlockState: unlockManager.unlockState,
                        savedItemID: nil,
                        savedUsageLogID: record.id.uuidString,
                        savedPlatforms: savedPlatforms()
                    )
                )
            } catch let error as VaultError {
                return BridgeResponseEnvelope(
                    id: request.id,
                    ok: false,
                    code: .validationError,
                    message: error.localizedDescription,
                    data: nil
                )
            } catch {
                return BridgeResponseEnvelope(
                    id: request.id,
                    ok: false,
                    code: .internalError,
                    message: error.localizedDescription,
                    data: nil
                )
            }
        }
    }

    private func showTransientMessage(_ message: String) {
        lastTransientMessage = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            if lastTransientMessage == message {
                lastTransientMessage = nil
            }
        }
    }
}
