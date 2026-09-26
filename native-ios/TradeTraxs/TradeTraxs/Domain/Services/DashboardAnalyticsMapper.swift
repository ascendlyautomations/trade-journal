import Foundation

/// Map Dashboard V3 analytical bundles → ``DashboardChartMetrics.Summary``.
nonisolated enum DashboardAnalyticsMapper {
    static func presetKey(for dateRange: DashboardDateRange) -> String {
        switch dateRange {
        case .sevenDays: return "d7"
        case .thirtyDays: return "d30"
        case .ninetyDays: return "d90"
        case .ytd: return "ytd"
        case .all: return "all"
        }
    }

    static func resolve(
        in bootstrap: AnalyticsDashboardBootstrapV3,
        accountFilter: DashboardAccountFilter,
        dateRange: DashboardDateRange,
        accountCharts: [String: AnalyticsDashboardChartsPresetV1]? = nil
    ) -> DashboardAnalyticsAccountMetricsLookup {
        let key = presetKey(for: dateRange)
        switch accountFilter {
        case .all:
            guard let bundle = bootstrap.data.aggregatePresets[key] else {
                return .accountMetricsMissing(accountID: "all", preset: key)
            }
            let charts = accountCharts?[key]
            let composed = composeAggregateBundle(base: bundle, charts: charts)
            return .aggregate(composed)
        case .account(let id):
            guard let metricsPreset = DashboardAnalyticsAccountMetricsLookup.metricsRow(
                accountID: id,
                in: bootstrap
            )?.presets[key] else {
                #if DEBUG
                print(
                    "[DashboardV3][AccountMetricsMissing] accountID=\(id.rawValue) preset=\(key)"
                )
                #endif
                return .accountMetricsMissing(accountID: id.rawValue, preset: key)
            }
            let charts = accountCharts?[key]
            let bundle = composeAccountBundle(metrics: metricsPreset, charts: charts)
            return .account(bundle, metricsSource: .accountPresetMetrics)
        }
    }

    static func bundle(
        in bootstrap: AnalyticsDashboardBootstrapV3,
        accountFilter: DashboardAccountFilter,
        dateRange: DashboardDateRange,
        accountCharts: [String: AnalyticsDashboardChartsPresetV1]? = nil
    ) -> AnalyticsDashboardPresetBundleV1? {
        switch resolve(in: bootstrap, accountFilter: accountFilter, dateRange: dateRange, accountCharts: accountCharts) {
        case .aggregate(let bundle), .account(let bundle, _):
            return bundle
        case .accountMetricsMissing:
            return nil
        }
    }

    private static func composeAggregateBundle(
        base: AnalyticsDashboardPresetBundleV1,
        charts: AnalyticsDashboardChartsPresetV1?
    ) -> AnalyticsDashboardPresetBundleV1 {
        guard let charts else { return base }
        return AnalyticsDashboardPresetBundleV1(
            preset: base.preset,
            start: base.start,
            end: base.end,
            metrics: base.metrics,
            equity: charts.equity,
            distributions: charts.distributions,
            insights: charts.insights
        )
    }

    /// Account KPIs always from ``metrics``; charts overlay when loaded (never aggregate KPI fallback).
    private static func composeAccountBundle(
        metrics: AnalyticsDashboardMetricsPresetV1,
        charts: AnalyticsDashboardChartsPresetV1?
    ) -> AnalyticsDashboardPresetBundleV1 {
        if let charts {
            return AnalyticsDashboardPresetBundleV1(
                preset: metrics.preset,
                start: metrics.start,
                end: metrics.end,
                metrics: metrics.metrics,
                equity: charts.equity,
                distributions: charts.distributions,
                insights: charts.insights
            )
        }
        return AnalyticsDashboardPresetBundleV1(
            preset: metrics.preset,
            start: metrics.start,
            end: metrics.end,
            metrics: metrics.metrics,
            equity: emptyEquity,
            distributions: emptyDistributions,
            insights: []
        )
    }

    private static let emptyEquity = AnalyticsDashboardEquityWireV1(
        points: [],
        max_drawdown: PostgresFlexibleDouble(0),
        current_equity: PostgresFlexibleDouble(0)
    )

    private static let emptyDistributions = AnalyticsDashboardDistributionsWireV1(
        sessions: [],
        symbols: [],
        daily: nil,
        streaks: nil,
        weekday_bars: [],
        weekday_heatmap: [],
        hour_bars: [],
        hour_heatmap: [],
        hour_highlights: nil,
        avg_hold_seconds: nil,
        avg_winner_hold_seconds: nil,
        avg_loser_hold_seconds: nil,
        hold_histogram: [],
        hold_extremes: nil,
        long_short: [],
        long_short_detail: nil,
        long_trade_count: 0,
        short_trade_count: 0,
        strategies: nil
    )

    static func summary(
        from bundle: AnalyticsDashboardPresetBundleV1,
        payoutTotal: Decimal?
    ) -> DashboardChartMetrics.Summary {
        let ingredients = DashboardAnalyticsComposer.ingredients(from: bundle.metrics)
        let equityPoints = mapEquity(bundle.equity)
        let dist = bundle.distributions

        let avgWin = DashboardAnalyticsComposer.averageWinner(ingredients)
        let avgLossMag = DashboardAnalyticsComposer.averageLoserMagnitude(ingredients)

        return DashboardChartMetrics.Summary(
            netPnL: ingredients.netPnL,
            winRate: DashboardAnalyticsComposer.winRate(ingredients),
            profitFactor: DashboardAnalyticsComposer.profitFactor(ingredients),
            payouts: payoutTotal,
            expectancy: DashboardAnalyticsComposer.expectancy(ingredients),
            averageRR: DashboardAnalyticsComposer.averageRR(ingredients),
            tradeCount: ingredients.tradeCount,
            winCount: ingredients.winCount,
            lossCount: ingredients.lossCount,
            avgWin: avgWin,
            avgLoss: avgLossMag.map { -$0 },
            bestTrade: ingredients.largestWin,
            biggestLoss: ingredients.largestLoss,
            maxDrawdown: decimal(bundle.equity.max_drawdown),
            currentEquity: decimal(bundle.equity.current_equity),
            equityData: equityPoints,
            sessions: mapSessions(dist.sessions),
            weekdays: mapBars(dist.weekday_bars),
            hours: mapBars(dist.hour_bars),
            longShort: mapBars(dist.long_short),
            longTradeCount: dist.long_trade_count,
            shortTradeCount: dist.short_trade_count,
            winLoss: [
                DashboardWinLossPoint(label: "Wins", count: ingredients.winCount),
                DashboardWinLossPoint(label: "Losses", count: ingredients.lossCount),
            ],
            holdTime: holdTimeRows(dist),
            holdTimeHistogram: dist.hold_histogram.map {
                DashboardHistogramBucket(label: $0.label, count: $0.count)
            },
            drawdownSeries: drawdownSeries(from: equityPoints),
            weekdayHeatmap: mapBars(dist.weekday_heatmap),
            hourHeatmap: mapBars(dist.hour_heatmap),
            insights: mapInsights(bundle.insights),
            sessionPerformance: mapSessionPerformance(dist.sessions),
            symbolPerformance: mapSymbolPerformance(dist.symbols ?? []),
            dailyPerformance: mapDaily(dist.daily),
            streaks: mapStreaks(dist.streaks),
            hourHighlights: mapHourHighlights(dist.hour_highlights),
            longShortComparison: mapLongShortDetail(dist.long_short_detail),
            holdExtremes: mapHoldExtremes(dist.hold_extremes),
            strategyHighlights: mapStrategies(dist.strategies)
        )
    }

    static func tradeCount(
        in bootstrap: AnalyticsDashboardBootstrapV3,
        accountFilter: DashboardAccountFilter,
        dateRange: DashboardDateRange
    ) -> Int {
        bundle(in: bootstrap, accountFilter: accountFilter, dateRange: dateRange)?.metrics.trade_count ?? 0
    }

    private static func mapEquity(_ equity: AnalyticsDashboardEquityWireV1) -> [ProfileStatisticsMetrics.EquityPoint] {
        equity.points.enumerated().map { offset, point in
            ProfileStatisticsMetrics.EquityPoint(
                index: point.i ?? offset,
                equity: decimal(point.v),
                date: parseBackendV2Timestamp(point.t)
            )
        }
    }

    private static func mapSessions(_ rows: [AnalyticsDashboardSessionWireV1]) -> [ProfileStatisticsMetrics.SessionRow] {
        rows.map { row in
            ProfileStatisticsMetrics.SessionRow(
                label: row.label,
                count: row.trade_count ?? row.count,
                pct: row.pct.value ?? 0
            )
        }
    }

    private static func mapSessionPerformance(
        _ rows: [AnalyticsDashboardSessionWireV1]
    ) -> [DashboardSessionPerformanceRow] {
        rows.map { row in
            DashboardSessionPerformanceRow(
                label: row.label,
                tradeCount: row.trade_count ?? row.count,
                netPnL: row.net_pnl?.value ?? 0,
                wins: row.wins ?? 0,
                losses: row.losses ?? 0,
                winRate: row.win_rate?.value
            )
        }
    }

    private static func mapSymbolPerformance(
        _ rows: [AnalyticsDashboardSymbolWireV1]
    ) -> [DashboardSymbolPerformanceRow] {
        rows.map { row in
            DashboardSymbolPerformanceRow(
                ticker: row.ticker,
                trades: row.trades,
                netPnL: row.net_pnl.value ?? 0,
                winRate: row.win_rate?.value,
                avgRR: row.avg_rr?.value
            )
        }
    }

    private static func mapDaily(_ wire: AnalyticsDashboardDailyWireV1?) -> DashboardDailyPerformanceSnapshot? {
        guard let wire else { return nil }
        return DashboardDailyPerformanceSnapshot(
            bestDayPnL: wire.best_day_pnl.value ?? 0,
            worstDayPnL: wire.worst_day_pnl.value ?? 0,
            avgDayPnL: wire.avg_day_pnl.value ?? 0,
            consistencyPct: wire.consistency_pct.value ?? 0,
            tradingDays: wire.trading_days
        )
    }

    private static func mapStreaks(_ wire: AnalyticsDashboardStreaksWireV1?) -> DashboardStreakSnapshot? {
        guard let wire else { return nil }
        return DashboardStreakSnapshot(
            currentStreak: wire.current_streak,
            currentType: wire.current_type,
            maxWinStreak: wire.max_win_streak,
            maxLossStreak: wire.max_loss_streak
        )
    }

    private static func mapHourHighlights(
        _ wire: AnalyticsDashboardHourHighlightsWireV1?
    ) -> DashboardHourHighlights? {
        guard let wire else { return nil }
        return DashboardHourHighlights(
            bestHour: wire.best_hour,
            worstHour: wire.worst_hour,
            bestPnL: wire.best_pnl?.value,
            worstPnL: wire.worst_pnl?.value
        )
    }

    private static func mapLongShortDetail(
        _ wire: AnalyticsDashboardLongShortDetailWireV1?
    ) -> DashboardLongShortComparison? {
        guard let wire else { return nil }
        return DashboardLongShortComparison(
            long: wire.long.map(mapDirectionSide),
            short: wire.short.map(mapDirectionSide)
        )
    }

    private static func mapDirectionSide(
        _ side: AnalyticsDashboardDirectionSideWireV1
    ) -> DashboardDirectionSideSnapshot {
        DashboardDirectionSideSnapshot(
            trades: side.trades,
            netPnL: side.net_pnl.value ?? 0,
            wins: side.wins,
            losses: side.losses,
            winRate: side.win_rate?.value,
            profitFactor: side.profit_factor?.value,
            expectancy: side.expectancy?.value,
            avgRR: side.avg_rr?.value,
            bestTrade: side.best_trade?.value,
            worstTrade: side.worst_trade?.value
        )
    }

    private static func mapHoldExtremes(
        _ wire: AnalyticsDashboardHoldExtremesWireV1?
    ) -> [DashboardHoldExtremeSnapshot] {
        guard let wire else { return [] }
        var rows: [DashboardHoldExtremeSnapshot] = []
        if let seconds = wire.fastest_winner_seconds?.value, seconds > 0 {
            rows.append(DashboardHoldExtremeSnapshot(
                label: "Fastest winner",
                durationSeconds: seconds,
                pnl: wire.fastest_winner_pnl?.value ?? 0
            ))
        }
        if let seconds = wire.longest_winner_seconds?.value, seconds > 0 {
            rows.append(DashboardHoldExtremeSnapshot(
                label: "Longest winner",
                durationSeconds: seconds,
                pnl: wire.longest_winner_pnl?.value ?? 0
            ))
        }
        if let seconds = wire.fastest_loser_seconds?.value, seconds > 0 {
            rows.append(DashboardHoldExtremeSnapshot(
                label: "Fastest loser",
                durationSeconds: seconds,
                pnl: wire.fastest_loser_pnl?.value ?? 0
            ))
        }
        if let seconds = wire.longest_loser_seconds?.value, seconds > 0 {
            rows.append(DashboardHoldExtremeSnapshot(
                label: "Longest loser",
                durationSeconds: seconds,
                pnl: wire.longest_loser_pnl?.value ?? 0
            ))
        }
        return rows
    }

    private static func mapStrategies(
        _ wire: AnalyticsDashboardStrategiesWireV1?
    ) -> DashboardStrategyHighlights? {
        guard let wire else { return nil }
        return DashboardStrategyHighlights(
            best: wire.best.map(mapStrategyHighlight),
            worst: wire.worst.map(mapStrategyHighlight)
        )
    }

    private static func mapStrategyHighlight(
        _ wire: AnalyticsDashboardStrategyHighlightWireV1
    ) -> DashboardStrategyHighlight {
        DashboardStrategyHighlight(
            strategy: wire.strategy,
            trades: wire.trades,
            netPnL: wire.net_pnl.value ?? 0,
            winRate: wire.win_rate?.value
        )
    }

    private static func mapBars(_ rows: [AnalyticsDashboardBarWireV1]) -> [DashboardBarPoint] {
        rows.map { row in
            DashboardBarPoint(
                label: row.label,
                value: row.value.value ?? 0
            )
        }
    }

    private static func mapInsights(_ rows: [AnalyticsDashboardInsightWireV1]) -> [DashboardInsightItem] {
        rows.compactMap { row in
            let kind: DashboardInsightKind = switch row.kind {
            case "session": .session
            case "symbol": .symbol
            case "direction": .direction
            default: .session
            }
            return DashboardInsightItem(id: row.id, title: row.title, body: row.body, kind: kind)
        }
    }

    private static func holdTimeRows(_ dist: AnalyticsDashboardDistributionsWireV1) -> [DashboardHoldTimeRow] {
        [
            DashboardHoldTimeRow(
                label: "Avg Hold",
                value: formatDuration(dist.avg_hold_seconds?.value)
            ),
            DashboardHoldTimeRow(
                label: "Avg Winner",
                value: formatDuration(dist.avg_winner_hold_seconds?.value)
            ),
            DashboardHoldTimeRow(
                label: "Avg Loser",
                value: formatDuration(dist.avg_loser_hold_seconds?.value)
            ),
        ]
    }

    private static func drawdownSeries(
        from equity: [ProfileStatisticsMetrics.EquityPoint]
    ) -> [DashboardDrawdownPoint] {
        var peak: Decimal = 0
        return equity.map { point in
            if point.equity > peak { peak = point.equity }
            let depth = peak - point.equity
            return DashboardDrawdownPoint(
                index: point.index,
                depth: -NSDecimalNumber(decimal: depth).doubleValue
            )
        }
    }

    private static func formatDuration(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "—" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(total)s"
    }

    private static func decimal(_ wire: PostgresFlexibleDouble) -> Decimal {
        guard let value = wire.value else { return 0 }
        return Decimal(value)
    }
}

nonisolated private func parseBackendV2Timestamp(_ string: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: string)
}
