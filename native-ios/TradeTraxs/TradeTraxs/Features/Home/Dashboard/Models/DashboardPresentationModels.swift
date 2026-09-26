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

/// Equity hero only — widens from the dashboard-selected preset until the curve can draw (≥2 trades).
/// Does not mutate ``DashboardViewModel/dateRange``.
nonisolated enum DashboardEquityChartRangeResolver {
    /// ``ProfileEquityCurveView`` needs at least two equity points (two closed trades in range).
    static let minimumTradeCountForEquityCurve = 2

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
        accountCharts: [String: AnalyticsDashboardChartsPresetV1]? = nil,
        allowAutomaticWiden: Bool = true
    ) -> DashboardDateRange {
        guard allowAutomaticWiden else { return requested }
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
        return .all
    }

    static func effectiveRange(
        requested: DashboardDateRange,
        tradeInputs: [DashboardChartMetrics.Input],
        accountFilter: DashboardAccountFilter,
        now: Date = Date(),
        allowAutomaticWiden: Bool = true
    ) -> DashboardDateRange {
        guard allowAutomaticWiden else { return requested }
        for range in widenOrder(from: requested) {
            let tradeCount = DashboardChartMetrics.filteredTrades(
                from: tradeInputs,
                accountFilter: accountFilter,
                dateRange: range,
                now: now
            ).count
            if tradeCount >= minimumTradeCountForEquityCurve {
                return range
            }
        }
        return .all
    }

    static func hasUsableEquityData(
        in bootstrap: AnalyticsDashboardBootstrapV3,
        accountFilter: DashboardAccountFilter,
        dateRange: DashboardDateRange,
        accountCharts: [String: AnalyticsDashboardChartsPresetV1]? = nil
    ) -> Bool {
        _ = accountCharts
        guard let bundle = DashboardAnalyticsMapper.bundle(
            in: bootstrap,
            accountFilter: accountFilter,
            dateRange: dateRange,
            accountCharts: accountCharts
        ) else {
            return false
        }
        return bundle.metrics.trade_count >= minimumTradeCountForEquityCurve
    }
}

/// Builds drawable equity series for user-selected presets with zero in-range trades.
nonisolated enum DashboardEquityChartSeries {
    static func carryForwardFlatIfNeeded(
        summary: DashboardChartMetrics.Summary,
        presetBundle: AnalyticsDashboardPresetBundleV1,
        analyticsBootstrap: AnalyticsDashboardBootstrapV3,
        accountFilter: DashboardAccountFilter,
        accountCharts: [String: AnalyticsDashboardChartsPresetV1]? = nil
    ) -> DashboardChartMetrics.Summary {
        guard summary.tradeCount == 0, summary.equityData.count < 2 else { return summary }
        guard let rangeStart = parseCalendarDay(presetBundle.start),
              let rangeEnd = parseCalendarDay(presetBundle.end, endOfDay: true)
        else { return summary }

        let prior = priorRealizedEquity(
            before: rangeStart,
            analyticsBootstrap: analyticsBootstrap,
            accountFilter: accountFilter,
            accountCharts: accountCharts
        )
        let points = [
            ProfileStatisticsMetrics.EquityPoint(index: 0, equity: prior, date: rangeStart),
            ProfileStatisticsMetrics.EquityPoint(index: 1, equity: prior, date: rangeEnd),
        ]
        return summaryWithChartEquity(summary, points: points, currentEquity: prior)
    }

    static func carryForwardFlatIfNeeded(
        summary: DashboardChartMetrics.Summary,
        dateRange: DashboardDateRange,
        tradeInputs: [DashboardChartMetrics.Input],
        accountFilter: DashboardAccountFilter,
        now: Date = Date()
    ) -> DashboardChartMetrics.Summary {
        guard summary.tradeCount == 0, summary.equityData.count < 2 else { return summary }
        guard let interval = dateRangeInterval(dateRange, now: now) else { return summary }

        let prior = priorRealizedEquity(
            tradeInputs: tradeInputs,
            accountFilter: accountFilter,
            before: interval.start,
            now: now
        )
        let points = [
            ProfileStatisticsMetrics.EquityPoint(index: 0, equity: prior, date: interval.start),
            ProfileStatisticsMetrics.EquityPoint(index: 1, equity: prior, date: interval.end),
        ]
        return summaryWithChartEquity(summary, points: points, currentEquity: prior)
    }

    private static func priorRealizedEquity(
        before rangeStart: Date,
        analyticsBootstrap: AnalyticsDashboardBootstrapV3,
        accountFilter: DashboardAccountFilter,
        accountCharts: [String: AnalyticsDashboardChartsPresetV1]?
    ) -> Decimal {
        guard let allBundle = DashboardAnalyticsMapper.bundle(
            in: analyticsBootstrap,
            accountFilter: accountFilter,
            dateRange: .all,
            accountCharts: accountCharts
        ) else { return 0 }
        let history = DashboardAnalyticsMapper.summary(from: allBundle, payoutTotal: nil).equityData
        let ordered = ProfileStatisticsMetrics.chartOrderedEquityPoints(history)
        if let lastBefore = ordered.last(where: { ($0.date ?? .distantPast) < rangeStart }) {
            return lastBefore.equity
        }
        return 0
    }

    private static func priorRealizedEquity(
        tradeInputs: [DashboardChartMetrics.Input],
        accountFilter: DashboardAccountFilter,
        before rangeStart: Date,
        now: Date
    ) -> Decimal {
        let beforeRange = DashboardChartMetrics.filteredTrades(
            from: tradeInputs,
            accountFilter: accountFilter,
            dateRange: .all,
            now: now
        ).filter { ($0.exitAt ?? $0.entryAt) < rangeStart }
        return beforeRange.reduce(Decimal(0)) { $0 + ($1.realizedPnL?.amount ?? 0) }
    }

    private static func summaryWithChartEquity(
        _ summary: DashboardChartMetrics.Summary,
        points: [ProfileStatisticsMetrics.EquityPoint],
        currentEquity: Decimal
    ) -> DashboardChartMetrics.Summary {
        var next = summary
        next.equityData = ProfileStatisticsMetrics.chartOrderedEquityPoints(points)
        next.currentEquity = currentEquity
        next.maxDrawdown = 0
        next.drawdownSeries = points.map {
            DashboardDrawdownPoint(index: $0.index, depth: 0)
        }
        return next
    }

    private static func dateRangeInterval(
        _ dateRange: DashboardDateRange,
        now: Date,
        calendar: Calendar = .current
    ) -> DateInterval? {
        switch dateRange {
        case .all:
            return DateInterval(start: .distantPast, end: now)
        case .sevenDays:
            guard let start = calendar.date(byAdding: .day, value: -7, to: now) else { return nil }
            return DateInterval(start: start, end: now)
        case .thirtyDays:
            guard let start = calendar.date(byAdding: .day, value: -30, to: now) else { return nil }
            return DateInterval(start: start, end: now)
        case .ninetyDays:
            guard let start = calendar.date(byAdding: .day, value: -90, to: now) else { return nil }
            return DateInterval(start: start, end: now)
        case .ytd:
            let year = calendar.component(.year, from: now)
            var comps = DateComponents()
            comps.year = year
            comps.month = 1
            comps.day = 1
            guard let start = calendar.date(from: comps) else { return nil }
            return DateInterval(start: start, end: now)
        }
    }

    private static func parseCalendarDay(_ string: String, endOfDay: Bool = false) -> Date? {
        let dayPart = String(string.prefix(10))
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let day = formatter.date(from: dayPart) else { return nil }
        guard endOfDay else { return day }
        return formatter.calendar.date(byAdding: DateComponents(day: 1, second: -1), to: day)
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

nonisolated struct DashboardSessionPerformanceRow: Identifiable, Hashable, Sendable {
    var id: String { label }
    var label: String
    var tradeCount: Int
    var netPnL: Double
    var wins: Int
    var losses: Int
    var winRate: Double?
}

nonisolated struct DashboardSymbolPerformanceRow: Identifiable, Hashable, Sendable {
    var id: String { ticker }
    var ticker: String
    var trades: Int
    var netPnL: Double
    var winRate: Double?
    var avgRR: Double?
}

nonisolated struct DashboardDailyPerformanceSnapshot: Hashable, Sendable {
    var bestDayPnL: Double
    var worstDayPnL: Double
    var avgDayPnL: Double
    var consistencyPct: Double
    var tradingDays: Int
}

nonisolated struct DashboardStreakSnapshot: Hashable, Sendable {
    var currentStreak: Int
    var currentType: String?
    var maxWinStreak: Int
    var maxLossStreak: Int
}

nonisolated struct DashboardHourHighlights: Hashable, Sendable {
    var bestHour: Int?
    var worstHour: Int?
    var bestPnL: Double?
    var worstPnL: Double?
}

nonisolated struct DashboardDirectionSideSnapshot: Hashable, Sendable {
    var trades: Int
    var netPnL: Double
    var wins: Int
    var losses: Int
    var winRate: Double?
    var profitFactor: Double?
    var expectancy: Double?
    var avgRR: Double?
    var bestTrade: Double?
    var worstTrade: Double?
}

nonisolated struct DashboardLongShortComparison: Hashable, Sendable {
    var long: DashboardDirectionSideSnapshot?
    var short: DashboardDirectionSideSnapshot?
}

nonisolated struct DashboardHoldExtremeSnapshot: Hashable, Sendable {
    var label: String
    var durationSeconds: Double
    var pnl: Double
}

nonisolated struct DashboardStrategyHighlight: Hashable, Sendable {
    var strategy: String
    var trades: Int
    var netPnL: Double
    var winRate: Double?
}

nonisolated struct DashboardStrategyHighlights: Hashable, Sendable {
    var best: DashboardStrategyHighlight?
    var worst: DashboardStrategyHighlight?
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
