import Foundation
import SwiftData

@Model
final class UsageLogRecord {
    @Attribute(.unique) var id: UUID
    var sourceProviderIdentity: String
    var sourceProviderDisplayName: String
    var sourceEnvironmentName: String
    var usage: String
    var usedSite: String
    var configurationLink: String?
    var serverIP: String?
    var currentURL: String
    var notes: String?
    var loggedAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        sourceProviderIdentity: String,
        sourceProviderDisplayName: String,
        sourceEnvironmentName: String,
        usage: String,
        usedSite: String,
        configurationLink: String?,
        serverIP: String?,
        currentURL: String,
        notes: String?,
        loggedAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.sourceProviderIdentity = sourceProviderIdentity
        self.sourceProviderDisplayName = sourceProviderDisplayName
        self.sourceEnvironmentName = sourceEnvironmentName
        self.usage = usage
        self.usedSite = usedSite
        self.configurationLink = configurationLink
        self.serverIP = serverIP
        self.currentURL = currentURL
        self.notes = notes
        self.loggedAt = loggedAt
        self.updatedAt = updatedAt
    }
}
