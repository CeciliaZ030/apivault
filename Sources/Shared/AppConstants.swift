import Foundation

enum AppConstants {
    static let appBundleIdentifier = "com.cecilia.APIKeyManager"
    static let bridgePort: UInt16 = 38173
    static let keychainService = "APIKeyManager.LocalVault"
}

enum EnvironmentPreset: String, CaseIterable, Codable, Identifiable {
    case development
    case staging
    case production
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .development: "Development"
        case .staging: "Staging"
        case .production: "Production"
        case .custom: "Custom"
        }
    }

    static func canonicalName(for rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return EnvironmentPreset.production.label }

        let lowered = trimmed.lowercased()
        for preset in EnvironmentPreset.allCases where preset != .custom {
            if lowered == preset.rawValue || lowered == preset.label.lowercased() {
                return preset.label
            }
        }

        return trimmed
    }
}
