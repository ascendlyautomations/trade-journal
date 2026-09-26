import Foundation

/// In-memory all-accounts Dashboard V3 chart bundles (equity/distributions/insights).
@MainActor
final class DashboardAnalyticsAggregateChartsStore {
    static let shared = DashboardAnalyticsAggregateChartsStore()

    private struct Key: Hashable {
        var revision: Int64
    }

    private var chartsByKey: [Key: [String: AnalyticsDashboardChartsPresetV1]] = [:]
    private var availabilityByKey: [Key: DashboardAnalyticsChartsAvailability] = [:]
    /// Set when a write names its owner. Unset writes stay visible for tests that never bind a viewer.
    private var ownerViewerID: String?

    private init() {}

    func availability(revision: Int64) -> DashboardAnalyticsChartsAvailability {
        guard cachedChartsVisible() else { return .notRequested }
        return availabilityByKey[Key(revision: revision)] ?? .notRequested
    }

    func charts(revision: Int64) -> [String: AnalyticsDashboardChartsPresetV1]? {
        guard cachedChartsVisible() else { return nil }
        return chartsByKey[Key(revision: revision)]
    }

    func markLoading(revision: Int64) {
        availabilityByKey[Key(revision: revision)] = .loading
    }

    func markLoaded(
        revision: Int64,
        presets: [String: AnalyticsDashboardChartsPresetV1],
        viewerID: String? = nil
    ) {
        guard claimOwner(viewerID) else { return }
        let key = Key(revision: revision)
        chartsByKey[key] = presets
        availabilityByKey[key] = .loaded
    }

    func markFailed(revision: Int64) {
        availabilityByKey[Key(revision: revision)] = .failed
    }

    func seed(
        revision: Int64,
        presets: [String: AnalyticsDashboardChartsPresetV1],
        viewerID: String? = nil
    ) {
        markLoaded(revision: revision, presets: presets, viewerID: viewerID)
    }

    func invalidate() {
        chartsByKey.removeAll()
        availabilityByKey.removeAll()
        ownerViewerID = nil
    }

    /// Drop cached presets that predate the visual-expansion distributions contract.
    func dropCharts(revision: Int64) {
        let key = Key(revision: revision)
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
}
