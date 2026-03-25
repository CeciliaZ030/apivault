import AppKit
import CryptoKit
import Foundation
import SwiftData

enum VaultError: LocalizedError {
    case validation(String)
    case duplicate(String)
    case locked
    case notFound

    var errorDescription: String? {
        switch self {
        case .validation(let message), .duplicate(let message):
            return message
        case .locked:
            return "Unlock the vault before revealing or copying keys."
        case .notFound:
            return "The selected key could not be found."
        }
    }

    var bridgeErrorCode: BridgeErrorCode {
        switch self {
        case .locked: .vaultLocked
        case .validation, .duplicate: .validationError
        case .notFound: .notFound
        }
    }
}

struct MetadataExportRecord: Codable {
    let id: UUID
    let providerSlug: String?
    let providerDisplayName: String
    let environment: String
    let keyName: String
    let platformURL: String?
    let sourceURL: String
    let pageTitle: String?
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
    let lastCopiedAt: Date?
    let lastSeenAt: Date?
    let status: String
}

@MainActor
final class VaultService {
    private let modelContext: ModelContext
    private let keychainService: KeychainService
    private let unlockManager: UnlockManager

    init(modelContext: ModelContext, keychainService: KeychainService, unlockManager: UnlockManager) {
        self.modelContext = modelContext
        self.keychainService = keychainService
        self.unlockManager = unlockManager
    }

    func saveDraft(_ draft: CaptureDraft) throws -> VaultItemRecord {
        let apiKey = draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw VaultError.validation("API key is required.")
        }

        let keyName = draft.keyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyName.isEmpty else {
            throw VaultError.validation("Key name is required.")
        }

        let providerDisplayName = resolveProviderDisplayName(slug: draft.providerSlug, customName: draft.providerDisplayName)
        let providerIdentity = normalizedProviderIdentity(slug: draft.providerSlug, displayName: providerDisplayName)
        let environment = normalizedEnvironmentName(draft.environment)
        let notes = normalizedOptionalString(draft.notes)
        let pageTitle = normalizedOptionalString(draft.pageTitle)
        let platformURL = normalizedOptionalString(draft.platformURL)
        let sourceURL = draft.sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let fingerprint = fingerprint(for: apiKey)

        let descriptor = FetchDescriptor<VaultItemRecord>(
            predicate: #Predicate<VaultItemRecord> {
                $0.providerIdentity == providerIdentity && $0.keyFingerprint == fingerprint
            }
        )

        if try !modelContext.fetch(descriptor).isEmpty {
            throw VaultError.duplicate("This key already exists for \(providerDisplayName).")
        }

        let id = UUID()
        let keychainAccount = id.uuidString

        try keychainService.save(secret: apiKey, account: keychainAccount)

        let record = VaultItemRecord(
            id: id,
            providerSlug: draft.providerSlug,
            providerDisplayName: providerDisplayName,
            providerIdentity: providerIdentity,
            environmentName: environment,
            keyName: keyName,
            keychainAccount: keychainAccount,
            keyFingerprint: fingerprint,
            platformURL: platformURL,
            sourceURL: sourceURL,
            pageTitle: pageTitle,
            notes: notes,
            createdAt: draft.capturedAt,
            updatedAt: draft.capturedAt,
            lastCopiedAt: nil,
            lastSeenAt: draft.capturedAt,
            statusRaw: "active"
        )

        modelContext.insert(record)

        do {
            try modelContext.save()
            return record
        } catch {
            try? keychainService.delete(account: keychainAccount)
            modelContext.delete(record)
            throw error
        }
    }

    func saveUsageLog(_ draft: UsageLogDraft) throws -> UsageLogRecord {
        let sourceProviderDisplayName = draft.sourceProviderDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceProviderDisplayName.isEmpty else {
            throw VaultError.validation("Source platform is required.")
        }

        let sourceEnvironment = normalizedEnvironmentName(draft.sourceEnvironment)
        let usage = draft.usage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !usage.isEmpty else {
            throw VaultError.validation("Usage description is required.")
        }

        let usedSite = draft.usedSite.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !usedSite.isEmpty else {
            throw VaultError.validation("Used site is required.")
        }

        let normalizedIdentity = normalizedProviderIdentity(
            slug: draft.sourceProviderIdentity,
            displayName: sourceProviderDisplayName
        )

        let record = UsageLogRecord(
            sourceProviderIdentity: normalizedIdentity,
            sourceProviderDisplayName: sourceProviderDisplayName,
            sourceEnvironmentName: sourceEnvironment,
            usage: usage,
            usedSite: usedSite,
            configurationLink: normalizedOptionalString(draft.configurationLink),
            serverIP: normalizedOptionalString(draft.serverIP),
            currentURL: draft.currentURL.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: normalizedOptionalString(draft.notes),
            loggedAt: draft.loggedAt,
            updatedAt: draft.loggedAt
        )

        modelContext.insert(record)
        try modelContext.save()
        return record
    }

    func delete(_ item: VaultItemRecord) throws {
        try keychainService.delete(account: item.keychainAccount)
        modelContext.delete(item)
        try modelContext.save()
    }

    func revealSecret(for item: VaultItemRecord) throws -> String {
        guard unlockManager.isUnlocked else {
            throw VaultError.locked
        }

        return try keychainService.read(account: item.keychainAccount)
    }

    func copySecret(for item: VaultItemRecord) throws {
        let secret = try revealSecret(for: item)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(secret, forType: .string)
        markCopied(item)
    }

    func copyAssignment(for item: VaultItemRecord) throws {
        let secret = try revealSecret(for: item)
        let keyName = (item.keyName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? item.keyName!
            : "API_KEY"

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(keyName)=\(secret)", forType: .string)
        markCopied(item)
    }

    private func markCopied(_ item: VaultItemRecord) {
        item.lastCopiedAt = Date()
        item.updatedAt = Date()
        try? modelContext.save()
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
        let trimmedProvider = providerDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProvider.isEmpty else {
            throw VaultError.validation("Provider name is required.")
        }

        let trimmedKeyName = keyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKeyName.isEmpty else {
            throw VaultError.validation("Key name is required.")
        }

        let normalizedProvider = normalizedProviderIdentity(slug: item.providerSlug, displayName: trimmedProvider)
        let trimmedEnvironment = normalizedEnvironmentName(environment)

        item.providerDisplayName = trimmedProvider
        item.providerIdentity = normalizedProvider
        item.environmentName = trimmedEnvironment
        item.keyName = trimmedKeyName
        item.platformURL = normalizedOptionalString(platformURL)
        item.sourceURL = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        item.pageTitle = normalizedOptionalString(pageTitle)
        item.notes = normalizedOptionalString(notes)
        item.updatedAt = Date()

        try modelContext.save()
    }

    func exportMetadata() throws -> Data {
        let descriptor = FetchDescriptor<VaultItemRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        let items = try modelContext.fetch(descriptor)
        let exportItems = items.map {
            MetadataExportRecord(
                id: $0.id,
                providerSlug: $0.providerSlug,
                providerDisplayName: $0.providerDisplayName,
                environment: $0.environmentName,
                keyName: $0.keyName ?? "",
                platformURL: $0.platformURL,
                sourceURL: $0.sourceURL,
                pageTitle: $0.pageTitle,
                notes: $0.notes,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                lastCopiedAt: $0.lastCopiedAt,
                lastSeenAt: $0.lastSeenAt,
                status: $0.statusRaw
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(exportItems)
    }

    private func resolveProviderDisplayName(slug: String?, customName: String?) -> String {
        if let provider = ProviderCatalog.provider(for: slug) {
            return provider.displayName
        }

        let trimmed = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return "Custom"
        }

        return trimmed
    }

    private func normalizedProviderIdentity(slug: String?, displayName: String) -> String {
        if let slug, !slug.isEmpty {
            return slug
        }

        return displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalizedEnvironmentName(_ rawValue: String) -> String {
        EnvironmentPreset.canonicalName(for: rawValue)
    }

    private func normalizedOptionalString(_ rawValue: String?) -> String? {
        guard let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func fingerprint(for secret: String) -> String {
        let digest = SHA256.hash(data: Data(secret.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
