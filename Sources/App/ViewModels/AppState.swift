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
    @Published private(set) var dataRevision: Int = 0

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
        markDataChanged()
        showTransientMessage("Vault locked.")
    }

    func unlockVault() async {
        do {
            try await unlockManager.unlock()
            markDataChanged()
            showTransientMessage("Vault unlocked for this session.")
        } catch {
            showTransientMessage(error.localizedDescription)
        }
    }

    func saveManualDraft(_ draft: CaptureDraft) throws {
        let record = try vaultService.saveDraft(draft)
        markDataChanged()
        showTransientMessage("Saved \(record.providerDisplayName) key.")
    }

    func saveManualDrafts(_ drafts: [CaptureDraft]) throws {
        let records = try vaultService.saveDrafts(drafts)
        markDataChanged()
        let name = records.first?.providerDisplayName ?? "Unknown"
        showTransientMessage("Saved \(records.count) key(s) for \(name).")
    }

    func saveUsageLog(_ draft: UsageLogDraft) throws {
        let record = try vaultService.saveUsageLog(draft)
        markDataChanged()
        showTransientMessage("Logged usage for \(record.sourceProviderDisplayName).")
    }

    func updateUsageLog(
        for record: UsageLogRecord,
        usage: String,
        usedSite: String,
        configurationLink: String,
        serverIP: String,
        notes: String
    ) throws {
        try vaultService.updateUsageLog(
            for: record,
            usage: usage,
            usedSite: usedSite,
            configurationLink: configurationLink,
            serverIP: serverIP,
            notes: notes
        )
        markDataChanged()
        showTransientMessage("Updated usage log.")
    }

    func deleteUsageLog(_ record: UsageLogRecord) throws {
        try vaultService.deleteUsageLog(record)
        markDataChanged()
        showTransientMessage("Deleted usage log.")
    }

    func delete(_ item: VaultItemRecord) throws {
        try vaultService.delete(item)
        markDataChanged()
        showTransientMessage("Deleted \(item.providerDisplayName).")
    }

    func revealSecret(for item: VaultItemRecord) throws -> String {
        try vaultService.revealSecret(for: item)
    }

    func revealSecrets(for items: [VaultItemRecord]) throws -> [UUID: String] {
        try vaultService.revealSecrets(for: items)
    }

    func copySecret(for item: VaultItemRecord) throws {
        try vaultService.copySecret(for: item)
        showTransientMessage("Copied \(item.providerDisplayName) key.")
    }

    func copyAssignment(for item: VaultItemRecord) throws {
        try vaultService.copyAssignment(for: item)
        let name = item.keyName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let label = name.isEmpty ? item.providerDisplayName : name
        showTransientMessage("Copied \(label)=…")
    }

    func updateSecret(for item: VaultItemRecord, newValue: String) throws {
        try vaultService.updateSecret(for: item, newValue: newValue)
        markDataChanged()
    }

    func updateKeyName(for item: VaultItemRecord, newName: String) throws {
        try vaultService.updateKeyName(for: item, newName: newName)
        markDataChanged()
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
        markDataChanged()
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

    func vaultItems() -> [VaultItemRecord] {
        let descriptor = FetchDescriptor<VaultItemRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return (try? modelContainer.mainContext.fetch(descriptor)) ?? []
    }

    func usageLogItems() -> [UsageLogRecord] {
        let descriptor = FetchDescriptor<UsageLogRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return (try? modelContainer.mainContext.fetch(descriptor)) ?? []
    }

    func savedPlatforms() -> [SavedPlatformOption] {
        let records = vaultItems()
        let logs = usageLogItems()

        return Dictionary(grouping: records, by: \.providerIdentity)
            .map { identity, grouped in
                let environments = Dictionary(
                    grouping: grouped.map { EnvironmentPreset.canonicalName(for: $0.environmentName) },
                    by: { $0.lowercased() }
                )
                .compactMap(\.value.first)
                .sorted()

                var keys: [String: [String]] = [:]
                for env in environments {
                    let envKeys = grouped
                        .filter { EnvironmentPreset.canonicalName(for: $0.environmentName) == env }
                        .compactMap { $0.keyName }
                        .filter { !$0.isEmpty }
                    keys[env] = envKeys
                }

                let providerLogs = logs.filter { $0.sourceProviderIdentity == identity }
                var usageProfiles: [String: [UsageProfile]] = [:]
                for env in environments {
                    let envLogs = providerLogs.filter {
                        EnvironmentPreset.canonicalName(for: $0.sourceEnvironmentName) == env
                    }
                    var seen = Set<String>()
                    var profiles: [UsageProfile] = []
                    for log in envLogs {
                        let dedup = "\(log.usage)|\(log.usedSite)|\(log.configurationLink ?? "")"
                        guard !seen.contains(dedup) else { continue }
                        seen.insert(dedup)
                        profiles.append(UsageProfile(
                            key: log.usage,
                            usedSite: log.usedSite,
                            configurationLink: log.configurationLink,
                            serverIP: log.serverIP,
                            notes: log.notes
                        ))
                    }
                    if !profiles.isEmpty {
                        usageProfiles[env] = profiles
                    }
                }

                return SavedPlatformOption(
                    identity: identity,
                    displayName: grouped.first?.providerDisplayName ?? "Unknown",
                    environments: environments,
                    keys: keys,
                    usageProfiles: usageProfiles
                )
            }
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    private func handleBridgeRequest(_ request: BridgeEnvelope) -> BridgeResponseEnvelope {
        switch request.type {
        case .ping, .requestStatus:
            return successResponse(id: request.id)

        case .openApp:
            activateApp()
            return successResponse(id: request.id, message: "Dashboard is open.")

        case .lockVault:
            lockVault()
            return successResponse(id: request.id, message: "Vault locked.")

        case .saveDraft:
            guard let draft = request.payload?.draft else {
                return errorResponse(id: request.id, code: .validationError, message: "Save request is missing its draft payload.")
            }

            do {
                let record = try vaultService.saveDraft(draft)
                markDataChanged()
                showTransientMessage("Saved \(record.providerDisplayName) key from Safari.")
                activateApp()
                return successResponse(id: request.id, message: "Saved \(record.providerDisplayName) key.", savedItemID: record.id.uuidString)
            } catch let error as VaultError {
                return errorResponse(id: request.id, code: error.bridgeErrorCode, message: error.localizedDescription)
            } catch {
                return errorResponse(id: request.id, code: .internalError, message: error.localizedDescription)
            }

        case .saveUsageLog:
            guard let draft = request.payload?.usageLogDraft else {
                return errorResponse(id: request.id, code: .validationError, message: "Usage log request is missing its payload.")
            }

            do {
                let record = try vaultService.saveUsageLog(draft)
                markDataChanged()
                showTransientMessage("Logged usage for \(record.sourceProviderDisplayName).")
                return successResponse(id: request.id, message: "Logged usage for \(record.sourceProviderDisplayName).", savedUsageLogID: record.id.uuidString)
            } catch let error as VaultError {
                return errorResponse(id: request.id, code: .validationError, message: error.localizedDescription)
            } catch {
                return errorResponse(id: request.id, code: .internalError, message: error.localizedDescription)
            }
        }
    }

    private func successResponse(id: String, message: String? = nil, savedItemID: String? = nil, savedUsageLogID: String? = nil) -> BridgeResponseEnvelope {
        BridgeResponseEnvelope(
            id: id,
            ok: true,
            code: nil,
            message: message,
            data: BridgeResponseData(
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                recognizedProvider: nil,
                unlockState: unlockManager.unlockState,
                savedItemID: savedItemID,
                savedUsageLogID: savedUsageLogID,
                savedPlatforms: savedPlatforms()
            )
        )
    }

    private func errorResponse(id: String, code: BridgeErrorCode, message: String) -> BridgeResponseEnvelope {
        BridgeResponseEnvelope(id: id, ok: false, code: code, message: message, data: nil)
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

    private func markDataChanged() {
        dataRevision &+= 1
    }
}
