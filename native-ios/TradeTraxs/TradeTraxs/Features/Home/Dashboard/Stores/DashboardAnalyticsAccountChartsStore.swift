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
    private var ownerViewerID: String?

    private init() {}

    func availability(accountID: TradingAccountID, revision: Int64) -> DashboardAnalyticsChartsAvailability {
        guard cachedChartsVisible() else { return .notRequested }
        return availabilityByKey[Key(accountID: normalized(accountID), revision: revision)] ?? .notRequested
    }

    func charts(
        accountID: TradingAccountID,
        revision: Int64
    ) -> [String: AnalyticsDashboardChartsPresetV1]? {
        guard cachedChartsVisible() else { return nil }
        return chartsByKey[Key(accountID: normalized(accountID), revision: revision)]
    }

    func markLoading(accountID: TradingAccountID, revision: Int64) {
        let key = Key(accountID: normalized(accountID), revision: revision)
        availabilityByKey[key] = .loading
    }

    func markLoaded(
        accountID: TradingAccountID,
        revision: Int64,
        presets: [String: AnalyticsDashboardChartsPresetV1],
        viewerID: String? = nil
    ) {
        guard claimOwner(viewerID) else { return }
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
        presets: [String: AnalyticsDashboardChartsPresetV1],
        viewerID: String? = nil
    ) {
        markLoaded(accountID: accountID, revision: revision, presets: presets, viewerID: viewerID)
    }

    func invalidate() {
        chartsByKey.removeAll()
        availabilityByKey.removeAll()
        ownerViewerID = nil
    }

    func dropCharts(accountID: TradingAccountID, revision: Int64) {
        let key = Key(accountID: normalized(accountID), revision: revision)
        chartsByKey.removeValue(forKey: key)
        availabilityByKey[key] = .notRequested
    }

    private func claimOwner(_ viewerID: String?) -> Bool {
        guard let viewerID else { return true }
        guard SessionViewerGate.shared.allowsDisplay(owner: viewerID) else { return false }
        let normalized = DashboardSessionIsolation.normalizedOwner(viewerID)
        if let ownerViewerID, ownerViewerID != normalized {
            chartsByKey.removeAll()
            availabilityByKey.removeAll()
        }
        ownerViewerID = normalized
        return true
    }

    private func cachedChartsVisible() -> Bool {
        guard let ownerViewerID else { return true }
        return SessionViewerGate.shared.allowsDisplay(owner: ownerViewerID)
    }

    private func normalized(_ id: TradingAccountID) -> String {
        DashboardAnalyticsAccountMetricsLookup.normalizedAccountID(id.rawValue)
    }
}
