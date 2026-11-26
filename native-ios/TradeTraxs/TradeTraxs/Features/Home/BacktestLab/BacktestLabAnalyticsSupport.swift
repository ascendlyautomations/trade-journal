import Foundation

/// Client analytics for Backtest Lab — dashboard math on scoped backtest trades only.
nonisolated enum BacktestLabAnalyticsSupport {
    static func chartInputs(from trades: [Trade]) -> [DashboardChartMetrics.Input] {
        trades.map { DashboardChartMetrics.Input(trade: $0, accountType: nil) }
    }

  /// Period KPIs + chart buckets; trades are already filtered by account, strategy, and time.
    static func computePeriodSummary(
        from periodTrades: [Trade],
        payoutTotal: Decimal? = nil
    ) -> DashboardChartMetrics.Summary {
        let inputs = chartInputs(from: periodTrades)
        guard !inputs.isEmpty else {
            return DashboardChartMetrics.compute(
                from: [],
                accountFilter: .all,
                interval: DateInterval(start: .distantPast, end: .distantFuture),
                payoutTotal: payoutTotal
            )
        }
        return DashboardChartMetrics.compute(
            from: inputs,
            accountFilter: .all,
            interval: DateInterval(start: .distantPast, end: .distantFuture),
            payoutTotal: payoutTotal
        )
    }

    static func insightsPresentation(
        summary: DashboardChartMetrics.Summary,
        periodTrades: [Trade],
        isLoading: Bool
    ) -> DashboardInsightsPresentation {
        DashboardInsightsComposer.build(
            serverInsights: summary.insights,
            trades: periodTrades,
            strategyHighlights: summary.strategyHighlights,
            isLoading: isLoading,
            tradeCount: summary.tradeCount,
            preferences: nil,
            includesPremiumAnalytics: true
        )
    }

    static func averageRealizedRr(for trades: [Trade]) -> Decimal? {
        TradePointsAndRealizedRr.averageRealizedRr(trades: trades)
    }

    static func payoffRatio(avgWin: Decimal?, avgLoss: Decimal?) -> Decimal? {
        guard let avgWin, let avgLoss, avgLoss > 0 else { return nil }
        return avgWin / avgLoss
    }

    static func lifetimeRealizedPnL(for trades: [Trade]) -> Decimal {
        trades.compactMap(\.realizedPnL?.amount).reduce(0, +)
    }

    static func metricChips(summary: DashboardChartMetrics.Summary) -> [DashboardMetricChip] {
        [
            DashboardMetricChip(
                id: "win",
                label: "Win Rate",
                value: summary.winRate.map(NumberDisplay.winRate)
                    ?? ProfileHeaderMetric.placeholderValue,
                tone: .neutral
            ),
            DashboardMetricChip(
                id: "pf",
                label: "Profit Factor",
                value: NumberDisplay.factor(summary.profitFactor),
                tone: {
                    guard let pf = summary.profitFactor else { return .neutral }
                    return pf >= 1 ? .positive : .negative
                }()
            ),
            DashboardMetricChip(
                id: "expectancy",
                label: "Expectancy",
                value: summary.expectancy.map { TradeDisplay.pnlText(Money(amount: $0)) } ?? "–",
                tone: {
                    guard let e = summary.expectancy else { return .neutral }
                    return e >= 0 ? .positive : .negative
                }()
            ),
            DashboardMetricChip(
                id: "rr",
                label: "Avg Target RR",
                value: summary.averageRR.map { NumberDisplay.ratio($0, fractionDigits: 2) } ?? "–",
                tone: .neutral
            ),
        ]
    }

    static func performanceCards(
        summary: DashboardChartMetrics.Summary,
        averageRealizedRr: Decimal?,
        payoff: Decimal?
    ) -> [DashboardMetricChip] {
        var cards: [DashboardMetricChip] = [
            DashboardMetricChip(
                id: "avgWin",
                label: "Avg Win",
                value: summary.avgWin.map { TradeDisplay.pnlText(Money(amount: $0)) } ?? "–",
                tone: .positive
            ),
            DashboardMetricChip(
                id: "avgLoss",
                label: "Avg Loss",
                value: summary.avgLoss.map { TradeDisplay.pnlText(Money(amount: -$0)) } ?? "–",
                tone: .negative
            ),
            DashboardMetricChip(
                id: "payoff",
                label: "Payoff Ratio",
                value: payoff.map { NumberDisplay.ratio($0, fractionDigits: 2) } ?? "–",
                tone: .neutral
            ),
            DashboardMetricChip(
                id: "realizedRR",
                label: "Avg Realized RR",
                value: averageRealizedRr.map { NumberDisplay.ratio($0, fractionDigits: 2) } ?? "–",
                tone: .neutral
            ),
            DashboardMetricChip(
                id: "dd",
                label: "Max Drawdown",
                value: summary.maxDrawdown > 0
                    ? TradeDisplay.pnlText(Money(amount: -summary.maxDrawdown))
                    : TradeDisplay.pnlText(Money(amount: 0)),
                tone: summary.maxDrawdown > 0 ? .negative : .neutral
            ),
        ]
        if let streaks = summary.streaks {
            cards.append(
                DashboardMetricChip(
                    id: "streaks",
                    label: "Win / Loss Streak",
                    value: "\(streaks.maxWinStreak) / \(streaks.maxLossStreak)",
                    tone: .neutral
                )
            )
        }
        return cards
    }
}