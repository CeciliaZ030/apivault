import Foundation

struct ProviderDefinition: Codable, Hashable, Identifiable {
    let slug: String
    let displayName: String
    let portalHosts: [String]
    let settingsPathHints: [String]
    let keyPatternHints: [String]

    var id: String { slug }
}

struct RecognizedProviderMatch: Codable, Hashable {
    let slug: String
    let displayName: String
    let reason: String
}

enum ProviderCatalog {
    static let supportedProviders: [ProviderDefinition] = [
        ProviderDefinition(
            slug: "openai",
            displayName: "OpenAI",
            portalHosts: ["platform.openai.com"],
            settingsPathHints: ["/settings", "/api-keys", "/settings/organization/api-keys"],
            keyPatternHints: ["sk-", "sess-"]
        ),
        ProviderDefinition(
            slug: "anthropic",
            displayName: "Anthropic",
            portalHosts: ["console.anthropic.com"],
            settingsPathHints: ["/settings/keys", "/settings", "/api-keys"],
            keyPatternHints: ["sk-ant-"]
        ),
        ProviderDefinition(
            slug: "stripe",
            displayName: "Stripe",
            portalHosts: ["dashboard.stripe.com"],
            settingsPathHints: ["/apikeys", "/developers", "/test/apikeys", "/live/apikeys"],
            keyPatternHints: ["sk_live_", "sk_test_", "rk_live_", "rk_test_"]
        )
    ]

    static func provider(for slug: String?) -> ProviderDefinition? {
        guard let slug else { return nil }
        return supportedProviders.first { $0.slug == slug }
    }

    static func recognize(urlString: String?) -> RecognizedProviderMatch? {
        guard let urlString, let components = URLComponents(string: urlString) else {
            return nil
        }

        if let fixtureProvider = components.queryItems?.first(where: { $0.name == "akm_provider" })?.value,
           let provider = provider(for: fixtureProvider) {
            return RecognizedProviderMatch(
                slug: provider.slug,
                displayName: provider.displayName,
                reason: "Fixture recognition matched \(provider.displayName)."
            )
        }

        guard let host = components.host?.lowercased() else {
            return nil
        }

        let path = components.path.lowercased()

        for provider in supportedProviders {
            guard provider.portalHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) else {
                continue
            }

            if let matchedHint = provider.settingsPathHints.first(where: { path.contains($0.lowercased()) }) {
                return RecognizedProviderMatch(
                    slug: provider.slug,
                    displayName: provider.displayName,
                    reason: "Recognized \(provider.displayName) from \(host)\(matchedHint)."
                )
            }

            return RecognizedProviderMatch(
                slug: provider.slug,
                displayName: provider.displayName,
                reason: "Recognized \(provider.displayName) from \(host)."
            )
        }

        return nil
    }
}

