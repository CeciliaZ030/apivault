import Foundation
import SwiftData

@Model
final class VaultItemRecord {
    @Attribute(.unique) var id: UUID
    var providerSlug: String?
    var providerDisplayName: String
    var providerIdentity: String
    var environmentName: String
    var keyName: String?
    @Attribute(.unique) var keychainAccount: String
    var keyFingerprint: String
    var platformURL: String?
    var sourceURL: String
    var pageTitle: String?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var lastCopiedAt: Date?
    var lastSeenAt: Date?
    var statusRaw: String

    init(
        id: UUID = UUID(),
        providerSlug: String?,
        providerDisplayName: String,
        providerIdentity: String,
        environmentName: String,
        keyName: String?,
        keychainAccount: String,
        keyFingerprint: String,
        platformURL: String?,
        sourceURL: String,
        pageTitle: String?,
        notes: String?,
        createdAt: Date,
        updatedAt: Date,
        lastCopiedAt: Date?,
        lastSeenAt: Date?,
        statusRaw: String
    ) {
        self.id = id
        self.providerSlug = providerSlug
        self.providerDisplayName = providerDisplayName
        self.providerIdentity = providerIdentity
        self.environmentName = environmentName
        self.keyName = keyName
        self.keychainAccount = keychainAccount
        self.keyFingerprint = keyFingerprint
        self.platformURL = platformURL
        self.sourceURL = sourceURL
        self.pageTitle = pageTitle
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastCopiedAt = lastCopiedAt
        self.lastSeenAt = lastSeenAt
        self.statusRaw = statusRaw
    }
}
