import Foundation

nonisolated enum DashboardAnalyticsChartsSupport {
    static func hasEquityPoints(_ presets: [String: AnalyticsDashboardChartsPresetV1]) -> Bool {
        presets.values.contains { !$0.equity.points.isEmpty }
    }
}
