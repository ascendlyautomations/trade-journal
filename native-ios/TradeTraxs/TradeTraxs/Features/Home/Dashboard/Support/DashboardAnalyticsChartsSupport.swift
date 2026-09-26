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

    /// Lazy chart overlay is usable for expanded Dashboard visuals (equity + post-expansion distributions).
    static func chartsReadyForPresentation(_ presets: [String: AnalyticsDashboardChartsPresetV1]) -> Bool {
        hasEquityPoints(presets) && hasVisualExpansionContract(presets)
    }

    static func samplePreset(
        _ presets: [String: AnalyticsDashboardChartsPresetV1]
    ) -> AnalyticsDashboardChartsPresetV1? {
        presets["d30"] ?? presets.values.first(where: { !$0.equity.points.isEmpty })
    }
}
