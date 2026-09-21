import Foundation

/// In-memory per-account Dashboard V3 chart bundles (equity/distributions/insights).
@MainActor
final class DashboardAnalyticsAccountChartsStore {
    static let shared = DashboardAnalyticsAccountChartsStore()

    private struct Key: Hashable {
        var accountID: String
        var revision: Int64
    }

    private var chartsByKey: [Key: [String: AnalyticsDashboardChartsPresetV1]] = [:]
    private var availabilityByKey: [Key: DashboardAnalyticsChartsAvailability] = [:]

    private init() {}

    func availability(accountID: TradingAccountID, revision: Int64) -> DashboardAnalyticsChartsAvailability {
        availabilityByKey[Key(accountID: normalized(accountID), revision: revision)] ?? .notRequested
    }

    func charts(
        accountID: TradingAccountID,
        revision: Int64
    ) -> [String: AnalyticsDashboardChartsPresetV1]? {
        chartsByKey[Key(accountID: normalized(accountID), revision: revision)]
    }

    func markLoading(accountID: TradingAccountID, revision: Int64) {
        let key = Key(accountID: normalized(accountID), revision: revision)
        availabilityByKey[key] = .loading
    }

    func markLoaded(
        accountID: TradingAccountID,
        revision: Int64,
        presets: [String: AnalyticsDashboardChartsPresetV1]
    ) {
        let key = Key(accountID: normalized(accountID), revision: revision)
        chartsByKey[key] = presets
        availabilityByKey[key] = .loaded
    }

    func markFailed(accountID: TradingAccountID, revision: Int64) {
        availabilityByKey[Key(accountID: normalized(accountID), revision: revision)] = .failed
    }

    func markNotRequested(accountID: TradingAccountID, revision: Int64) {
        availabilityByKey[Key(accountID: normalized(accountID), revision: revision)] = .notRequested
    }

    func seed(
        accountID: TradingAccountID,
        revision: Int64,
        presets: [String: AnalyticsDashboardChartsPresetV1]
    ) {
        markLoaded(accountID: accountID, revision: revision, presets: presets)
    }

    func invalidate() {
        chartsByKey.removeAll()
        availabilityByKey.removeAll()
    }

    private func normalized(_ id: TradingAccountID) -> String {
        DashboardAnalyticsAccountMetricsLookup.normalizedAccountID(id.rawValue)
    }
}
