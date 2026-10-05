import Foundation

nonisolated enum DashboardAnalyticsChartsSupport {
    static func hasEquityPoints(_ presets: [String: AnalyticsDashboardChartsPresetV1]) -> Bool {
        presets.values.contains { !$0.equity.points.isEmpty }
    }

    /// Charts bundle after `20260925163000` always includes these distribution keys (JSON), even when empty.
    static func hasVisualExpansionContract(_ presets: [String: AnalyticsDashboardChartsPresetV1]) -> Bool {
        guard hasEquityPoints(presets) else { return true }
        guard let sample = samplePreset(presets) else { return false }
        return distributionsIncludeVisualExpansion(sample.distributions)
    }

    static func distributionsIncludeVisualExpansion(
        _ distributions: AnalyticsDashboardDistributionsWireV1
    ) -> Bool {
        distributions.symbols != nil && distributions.streaks != nil
    }

    /// A fetched overlay is ready once it can be shown.
    /// Fewer than two equity points is a resolved empty curve, not an unfinished request.
    /// A drawable curve still has to include the distribution expansion keys.
    static func chartsReadyForPresentation(_ presets: [String: AnalyticsDashboardChartsPresetV1]) -> Bool {
        guard !presets.isEmpty else { return false }
        let longestSeries = presets.values.map(\.equity.points.count).max() ?? 0
        if longestSeries < DashboardEquityChartRangeResolver.minimumTradeCountForEquityCurve {
            return true
        }
        return hasVisualExpansionContract(presets)
    }

    static func samplePreset(
        _ presets: [String: AnalyticsDashboardChartsPresetV1]
    ) -> AnalyticsDashboardChartsPresetV1? {
        presets["d30"] ?? presets.values.first(where: { !$0.equity.points.isEmpty })
    }
}
