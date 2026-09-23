import Foundation

/// Dashboard date-range presets — mirrors web `timeFilter` ids.
nonisolated enum DashboardDateRange: String, CaseIterable, Identifiable, Sendable {
    case all
    case sevenDays
    case thirtyDays
    case ninetyDays
    case ytd

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All Time"
        case .sevenDays: return "7D"
        case .thirtyDays: return "30D"
        case .ninetyDays: return "90D"
        case .ytd: return "YTD"
        }
    }

    func contains(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch self {
        case .all:
            return true
        case .sevenDays:
            guard let start = calendar.date(byAdding: .day, value: -7, to: now) else { return true }
            return date >= start
        case .thirtyDays:
            guard let start = calendar.date(byAdding: .day, value: -30, to: now) else { return true }
            return date >= start
        case .ninetyDays:
            guard let start = calendar.date(byAdding: .day, value: -90, to: now) else { return true }
            return date >= start
        case .ytd:
            let year = calendar.component(.year, from: now)
            var comps = DateComponents()
            comps.year = year
            comps.month = 1
            comps.day = 1
            guard let start = calendar.date(from: comps) else { return true }
            return date >= start
        }
    }
}

/// Per-account Home date-range resolution — prefer 30D when it has enough trades for a
/// meaningful equity curve (2+), else the next wider preset; single-trade accounts use All Time.
nonisolated enum DashboardDateRangeFallback {
    /// Minimum trades required before an automatic preset is considered useful for the equity curve.
    static let minimumTradeCountForInitialRange = 2

    /// Wider presets after the default 30D window (7D omitted — narrower than 30D).
    static let initialLoadOrder: [DashboardDateRange] = [
        .thirtyDays,
        .ninetyDays,
        .ytd,
        .all,
    ]

    static func initialEffectiveRange(
        analyticsBootstrap: AnalyticsDashboardBootstrapV3,
        accountFilter: DashboardAccountFilter
    ) -> DashboardDateRange {
        for range in initialLoadOrder {
            let tradeCount = DashboardAnalyticsMapper.tradeCount(
                in: analyticsBootstrap,
                accountFilter: accountFilter,
                dateRange: range
            )
            if tradeCount >= minimumTradeCountForInitialRange {
                return range
            }
        }
        let allTimeCount = DashboardAnalyticsMapper.tradeCount(
            in: analyticsBootstrap,
            accountFilter: accountFilter,
            dateRange: .all
        )
        if allTimeCount >= 1 {
            return .all
        }
        return .thirtyDays
    }

    static func initialEffectiveRange(
        tradeInputs: [DashboardChartMetrics.Input],
        accountFilter: DashboardAccountFilter,
        now: Date = Date()
    ) -> DashboardDateRange {
        for range in initialLoadOrder {
            let tradeCount = filteredTradeCount(
                tradeInputs: tradeInputs,
                accountFilter: accountFilter,
                dateRange: range,
                now: now
            )
            if tradeCount >= minimumTradeCountForInitialRange {
                return range
            }
        }

        let allTimeCount = filteredTradeCount(
            tradeInputs: tradeInputs,
            accountFilter: accountFilter,
            dateRange: .all,
            now: now
        )
        if allTimeCount >= 1 {
            return .all
        }
        return .thirtyDays
    }

    private static func filteredTradeCount(
        tradeInputs: [DashboardChartMetrics.Input],
        accountFilter: DashboardAccountFilter,
        dateRange: DashboardDateRange,
        now: Date
    ) -> Int {
        DashboardChartMetrics.filteredTrades(
            from: tradeInputs,
            accountFilter: accountFilter,
            dateRange: dateRange,
            now: now
        ).count
    }
}

/// Equity hero only — widens from the dashboard-selected preset until chart data exists.
/// Does not mutate ``DashboardViewModel/dateRange``.
nonisolated enum DashboardEquityChartRangeResolver {
    static let supportedWidenOrder: [DashboardDateRange] = [
        .sevenDays,
        .thirtyDays,
        .ninetyDays,
        .ytd,
        .all,
    ]

    static func widenOrder(from requested: DashboardDateRange) -> [DashboardDateRange] {
        guard let start = supportedWidenOrder.firstIndex(of: requested) else {
            return [.thirtyDays, .ninetyDays, .ytd, .all]
        }
        return Array(supportedWidenOrder[start...])
    }

    static func effectiveRange(
        requested: DashboardDateRange,
        analyticsBootstrap: AnalyticsDashboardBootstrapV3,
        accountFilter: DashboardAccountFilter,
        accountCharts: [String: AnalyticsDashboardChartsPresetV1]? = nil
    ) -> DashboardDateRange {
        for range in widenOrder(from: requested) {
            if hasUsableEquityData(
                in: analyticsBootstrap,
                accountFilter: accountFilter,
                dateRange: range,
                accountCharts: accountCharts
            ) {
                return range
            }
        }
        return requested
    }

    static func effectiveRange(
        requested: DashboardDateRange,
        tradeInputs: [DashboardChartMetrics.Input],
        accountFilter: DashboardAccountFilter,
        now: Date = Date()
    ) -> DashboardDateRange {
        for range in widenOrder(from: requested) {
            let tradeCount = DashboardChartMetrics.filteredTrades(
                from: tradeInputs,
                accountFilter: accountFilter,
                dateRange: range,
                now: now
            ).count
            if tradeCount > 0 {
                return range
            }
        }
        return requested
    }

    static func hasUsableEquityData(
        in bootstrap: AnalyticsDashboardBootstrapV3,
        accountFilter: DashboardAccountFilter,
        dateRange: DashboardDateRange,
        accountCharts: [String: AnalyticsDashboardChartsPresetV1]? = nil
    ) -> Bool {
        guard let bundle = DashboardAnalyticsMapper.bundle(
            in: bootstrap,
            accountFilter: accountFilter,
            dateRange: dateRange,
            accountCharts: accountCharts
        ) else {
            return false
        }
        if bundle.metrics.trade_count > 0 {
            return true
        }
        return !bundle.equity.points.isEmpty
    }
}

nonisolated enum DashboardAccountFilter: Hashable, Sendable {
    case all
    case account(TradingAccountID)

    var title: String {
        switch self {
        case .all: return "All Accounts"
        case .account: return "Account"
        }
    }
}

nonisolated enum DashboardLoadPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(String)
}

nonisolated struct DashboardMetricChip: Identifiable, Hashable, Sendable {
    var id: String
    var label: String
    var value: String
    var tone: DashboardMetricTone
}

nonisolated enum DashboardMetricTone: Hashable, Sendable {
    case neutral
    case positive
    case negative
}

nonisolated struct DashboardBarPoint: Identifiable, Hashable, Sendable {
    var id: String { label }
    var label: String
    var value: Double
}

nonisolated struct DashboardWinLossPoint: Identifiable, Hashable, Sendable {
    var id: String { label }
    var label: String
    var count: Int
}

nonisolated struct DashboardHoldTimeRow: Identifiable, Hashable, Sendable {
    var id: String { label }
    var label: String
    var value: String
}

nonisolated struct DashboardHistogramBucket: Identifiable, Hashable, Sendable {
    var id: String { label }
    var label: String
    var count: Int
}

nonisolated struct DashboardDrawdownPoint: Identifiable, Hashable, Sendable {
    var index: Int
    /// Negative depth below peak (0 at equity highs).
    var depth: Double
    var id: Int { index }
}

nonisolated enum DashboardInsightKind: String, Hashable, Sendable {
    case session
    case symbol
    case direction
}

nonisolated struct DashboardInsightItem: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var body: String
    var kind: DashboardInsightKind

    /// Display copy — em dashes normalized to commas (templates + future dynamic text).
    var displayTitle: String { GeneratedProseNormalizer.normalize(title) }
    var displayBody: String { GeneratedProseNormalizer.normalize(body) }
}
