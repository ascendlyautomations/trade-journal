import Foundation

nonisolated protocol TradingPreferencesRepository: Sendable {
    func globalPreferences(for userID: ProfileID) async throws -> TradingPreferenceGlobal
    func saveGlobal(_ preferences: TradingPreferenceGlobal) async throws -> TradingPreferenceGlobal
    func accountOverrides(for userID: ProfileID) async throws -> [TradingPreferenceAccountOverride]
    func saveOverride(
        _ override: TradingPreferenceAccountOverride
    ) async throws -> TradingPreferenceAccountOverride
    func revisions(for userID: ProfileID) async throws -> [TradingPreferenceRevision]
    func discovery(for userID: ProfileID) async throws -> PreferenceDiscoveryResponse?
    func recordDiscovery(
        _ response: PreferenceDiscoveryResponse,
        for userID: ProfileID
    ) async throws -> PreferenceDiscoveryResponse
    func hasJournalTrade(for userID: ProfileID) async throws -> Bool
}
