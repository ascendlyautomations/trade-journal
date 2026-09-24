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

    private init() {}

    func availability(revision: Int64) -> DashboardAnalyticsChartsAvailability {
        availabilityByKey[Key(revision: revision)] ?? .notRequested
    }

    func charts(revision: Int64) -> [String: AnalyticsDashboardChartsPresetV1]? {
        chartsByKey[Key(revision: revision)]
    }

    func markLoading(revision: Int64) {
        availabilityByKey[Key(revision: revision)] = .loading
    }

    func markLoaded(revision: Int64, presets: [String: AnalyticsDashboardChartsPresetV1]) {
        let key = Key(revision: revision)
        chartsByKey[key] = presets
        availabilityByKey[key] = .loaded
    }

    func markFailed(revision: Int64) {
        availabilityByKey[Key(revision: revision)] = .failed
    }

    func seed(revision: Int64, presets: [String: AnalyticsDashboardChartsPresetV1]) {
        markLoaded(revision: revision, presets: presets)
    }

    func invalidate() {
        chartsByKey.removeAll()
        availabilityByKey.removeAll()
    }
}
