import Foundation

/// Profile → Stats equity curve minimum-trade UX (aligned with ``DashboardEquityChartRangeResolver``).
nonisolated enum ProfileStatsEquityCurvePresentation {
    static let singleTradeDetail = "Equity curve will display with 2 or more trades."
    static let singleTradeAccessibilityLabel = singleTradeDetail
}
