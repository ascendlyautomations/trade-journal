import Foundation

/// Searchable broker integration entries for Settings → Broker Integrations.
enum BrokerIntegrationsCatalog {
    static let providers: [BrokerIntegrationProvider] = [.tradovate, .rithmic]

    static func displayName(for provider: BrokerIntegrationProvider) -> String {
        BrokerIntegrationDisplay.providerLabel(provider)
    }

    static func matchesSearch(_ provider: BrokerIntegrationProvider, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return displayName(for: provider).localizedCaseInsensitiveContains(trimmed)
    }

    static func filteredProviders(matching query: String) -> [BrokerIntegrationProvider] {
        providers.filter { matchesSearch($0, query: query) }
    }
}
