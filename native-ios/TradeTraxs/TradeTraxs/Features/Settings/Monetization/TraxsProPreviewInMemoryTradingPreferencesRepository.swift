import Foundation

/// Ephemeral sample trading preferences for TraxsPro preview only — never touches production caches or Supabase.
nonisolated final class TraxsProPreviewInMemoryTradingPreferencesRepository: TradingPreferencesRepository,
    @unchecked Sendable
{
    private let context: PreferenceRuleContext

    init(profileID: ProfileID) {
        context = DemoCanonicalDataset.previewPreferenceContext(for: profileID)
    }

    func globalPreferences(for userID: ProfileID) async throws -> TradingPreferenceGlobal {
        guard let global = context.global, userID == global.userID else {
            return .empty(userID: userID)
        }
        return global
    }

    func accountOverrides(for userID: ProfileID) async throws -> [TradingPreferenceAccountOverride] {
        guard let global = context.global, userID == global.userID else { return [] }
        return context.overrides
    }

    func revisions(for userID: ProfileID) async throws -> [TradingPreferenceRevision] {
        guard let global = context.global, userID == global.userID else { return [] }
        return context.revisions
    }

    func saveGlobal(_ preferences: TradingPreferenceGlobal) async throws -> TradingPreferenceGlobal {
        throw DemoAuthRequired.error
    }

    func saveOverride(
        _ override: TradingPreferenceAccountOverride
    ) async throws -> TradingPreferenceAccountOverride {
        throw DemoAuthRequired.error
    }

    func discovery(for userID: ProfileID) async throws -> PreferenceDiscoveryResponse? {
        nil
    }

    func recordDiscovery(
        _ response: PreferenceDiscoveryResponse,
        for userID: ProfileID
    ) async throws -> PreferenceDiscoveryResponse {
        throw DemoAuthRequired.error
    }

    func hasJournalTrade(for userID: ProfileID) async throws -> Bool {
        !DemoCanonicalDataset.trades().filter { $0.mode != .backtest }.isEmpty
    }
}