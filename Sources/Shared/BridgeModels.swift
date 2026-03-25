import Foundation

enum BridgeMessageType: String, Codable {
    case ping
    case saveDraft
    case saveUsageLog
    case openApp
    case lockVault
    case requestStatus
}

enum BridgeErrorCode: String, Codable {
    case validationError = "validation_error"
    case vaultLocked = "vault_locked"
    case notFound = "not_found"
    case internalError = "internal_error"
}

enum UnlockState: String, Codable {
    case locked
    case unlockedSession = "unlocked(session)"
}

struct BridgeEnvelope: Codable {
    let id: String
    let type: BridgeMessageType
    let payload: BridgePayload?
}

struct BridgePayload: Codable {
    let draft: CaptureDraft?
    let usageLogDraft: UsageLogDraft?
    let statusRequest: StatusRequest?
}

struct StatusRequest: Codable {
    let sourceURL: String?
    let pageTitle: String?
}

struct CaptureDraft: Codable {
    let providerSlug: String?
    let providerDisplayName: String?
    let keyName: String
    let apiKey: String
    let platformURL: String?
    let sourceURL: String
    let pageTitle: String
    let notes: String?
    let environment: String
    let capturedAt: Date
}

struct UsageLogDraft: Codable {
    let sourceProviderIdentity: String?
    let sourceProviderDisplayName: String
    let sourceEnvironment: String
    let usage: String
    let usedSite: String
    let configurationLink: String?
    let serverIP: String?
    let currentURL: String
    let notes: String?
    let loggedAt: Date
}

struct SavedPlatformOption: Codable, Hashable, Identifiable {
    let identity: String
    let displayName: String
    let environments: [String]

    var id: String { identity }
}

struct BridgeResponseEnvelope: Codable {
    let id: String
    let ok: Bool
    let code: BridgeErrorCode?
    let message: String?
    let data: BridgeResponseData?
}

struct BridgeResponseData: Codable {
    let appVersion: String?
    let recognizedProvider: RecognizedProviderMatch?
    let unlockState: UnlockState?
    let savedItemID: String?
    let savedUsageLogID: String?
    let savedPlatforms: [SavedPlatformOption]?
}
