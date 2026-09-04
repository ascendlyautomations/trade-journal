import Foundation

/// Owner-only trade detail comparisons — RPC-first with scoped local fallback.
nonisolated enum TradeDetailAnalytics {
    static let minCohortTrades = 5
    static let minTickerTradesForComparison = 3

    struct CohortComparison: Equatable, Sendable {
        var avgPnL: Decimal
        var avgRR: Decimal?
        var avgHoldSeconds: Int?
        var tradeCount: Int
        var pnlPercentile: Double?
        var rrPercentile: Double?
        var holdShorterThanPercent: Double?
        var findings: [String]
    }

    struct QuickInsight: Equatable, Sendable {
        var symbol: String
        var title: String
        var message: String
    }

    struct TickerHistory: Equatable, Sendable {
        var ticker: String
        var previousTradeCount: Int
        var winRate: Decimal?
        var totalPnL: Decimal
        var profitFactor: Decimal?
        var avgTradePnL: Decimal?
        var comparisonSentence: String
    }

    struct Result: Equatable, Sendable {
        var cohort: CohortComparison?
        var tickerHistory: TickerHistory?
        var quickInsight: QuickInsight?
    }

    static func analyze(
        trade: Trade,
        history: [Trade],
        accountModes: [TradingAccountID: TradingAccountMode] = [:]
    ) -> Result {
        let peers = TradeDetailComparisonScope.previousOwnerTrades(
            history: history,
            currentTrade: trade,
            accountModes: accountModes
        )
        let cohort = buildCohortComparison(trade: trade, peers: peers)
        let tickerHistory = buildTickerHistory(trade: trade, peers: peers)
        let insight = buildQuickInsight(trade: trade, peers: peers, cohort: cohort, ticker: tickerHistory)
        return Result(cohort: cohort, tickerHistory: tickerHistory, quickInsight: insight)
    }

    static func holdSeconds(for trade: Trade) -> Int? {
        if let seconds = trade.durationSeconds, seconds > 0 { return seconds }
        guard let exit = trade.exitAt else { return nil }
        return max(0, Int(exit.timeIntervalSince(trade.entryAt)))
    }

    // MARK: - Cohort

    private static func buildCohortComparison(trade: Trade, peers: [Trade]) -> CohortComparison? {
        guard peers.count >= minCohortTrades else { return nil }

        let pnls = peers.map(TradeDetailComparisonScope.netPnL)
        let avgPnL = pnls.reduce(0, +) / Decimal(pnls.count)
        let avgRR = averageRR(peers)
        let avgHold = averageHoldSeconds(peers)

        var findings: [String] = []

        if let tradeRR = trade.riskReward, let avgRR, avgRR > 0 {
            let delta = NSDecimalNumber(decimal: tradeRR - avgRR).doubleValue
            if abs(delta) >= 0.3 {
                findings.append(String(format: "%.1fR %@ your average trade", abs(delta), delta >= 0 ? "better than" : "worse than"))
            }
        }

        if let tradePnL = trade.realizedPnL?.amount {
            let percentile = percentileRank(value: tradePnL, in: pnls, higherIsBetter: true)
            if percentile >= 88 {
                findings.append(String(format: "Top %.0f%% of your trades by P&L", 100 - percentile))
            } else if percentile <= 12, tradePnL < 0 {
                findings.append(String(format: "Bottom %.0f%% of your trades by P&L", percentile))
            }
        }

        var holdShorterThanPercent: Double?
        if let tradeHold = holdSeconds(for: trade) {
            let holdSamples = peers.compactMap { holdSeconds(for: $0) }
            if holdSamples.count >= minCohortTrades {
                let shorterCount = holdSamples.filter { $0 > tradeHold }.count
                let holdPercent = Double(shorterCount) / Double(holdSamples.count) * 100
                holdShorterThanPercent = holdPercent
                if holdPercent >= 60 {
                    findings.append(String(format: "Shorter hold time than %.0f%% of your trades", holdPercent))
                } else if holdPercent <= 25 {
                    findings.append(String(format: "Longer hold time than %.0f%% of your trades", 100 - holdPercent))
                }
            }
        }

        return CohortComparison(
            avgPnL: avgPnL,
            avgRR: avgRR,
            avgHoldSeconds: avgHold,
            tradeCount: peers.count,
            pnlPercentile: trade.realizedPnL.map { percentileRank(value: $0.amount, in: pnls, higherIsBetter: true) },
            rrPercentile: trade.riskReward.flatMap { rr in
                let samples = peers.compactMap(\.riskReward)
                guard samples.count >= minCohortTrades else { return nil }
                return percentileRank(value: rr, in: samples, higherIsBetter: true)
            },
            holdShorterThanPercent: holdShorterThanPercent,
            findings: Array(findings.prefix(3))
        )
    }

    // MARK: - Ticker

    private static func buildTickerHistory(trade: Trade, peers: [Trade]) -> TickerHistory? {
        let ticker = TradeDetailComparisonScope.normalizedTicker(trade.symbol.ticker)
        guard !ticker.isEmpty else { return nil }

        let sameTicker = peers.filter {
            TradeDetailComparisonScope.tickersMatch($0.symbol.ticker, ticker)
        }
        let previousCount = sameTicker.count
        let pnls = sameTicker.map(TradeDetailComparisonScope.netPnL)
        let wins = pnls.filter { $0 > 0 }.count
        let totalPnL = pnls.reduce(0, +)
        let winRate: Decimal? = previousCount > 0 ? Decimal(wins) / Decimal(previousCount) : nil
        let avgTradePnL: Decimal? = previousCount > 0 ? totalPnL / Decimal(previousCount) : nil
        let profitFactor = profitFactor(from: pnls)

        let comparisonSentence: String
        if previousCount < minTickerTradesForComparison {
            comparisonSentence = "Not enough previous \(ticker) trades to compare yet."
        } else if trade.realizedPnL != nil {
            let tradePnL = TradeDetailComparisonScope.netPnL(for: trade)
            let betterCount = pnls.filter { $0 < tradePnL }.count
            comparisonSentence =
                "This trade performed better than \(betterCount) of your previous \(previousCount) \(ticker) trades."
        } else {
            comparisonSentence = "Not enough previous \(ticker) trades to compare yet."
        }

        return TickerHistory(
            ticker: ticker,
            previousTradeCount: previousCount,
            winRate: winRate,
            totalPnL: totalPnL,
            profitFactor: profitFactor,
            avgTradePnL: avgTradePnL,
            comparisonSentence: comparisonSentence
        )
    }

    // MARK: - Quick insight

    private static func buildQuickInsight(
        trade: Trade,
        peers: [Trade],
        cohort: CohortComparison?,
        ticker: TickerHistory?
    ) -> QuickInsight? {
        if let tradeRR = trade.riskReward,
           let percentile = cohort?.rrPercentile,
           percentile >= 90,
           tradeRR > 0
        {
            return QuickInsight(
                symbol: "🔥",
                title: "Strong Trade",
                message: String(format: "Top %.0f%% of your trades by RR", 100 - percentile)
            )
        }

        let tradePnL = TradeDetailComparisonScope.netPnL(for: trade)
        if tradePnL < 0 {
            let lossAmounts = peers
                .map(TradeDetailComparisonScope.netPnL)
                .filter { $0 < 0 }
                .map { abs($0) }
            if lossAmounts.count >= minCohortTrades {
                let avgLoss = lossAmounts.reduce(0, +) / Decimal(lossAmounts.count)
                let ratio = NSDecimalNumber(decimal: abs(tradePnL) / avgLoss).doubleValue
                if ratio >= 1.5 {
                    return QuickInsight(
                        symbol: "⚠️",
                        title: "Larger Than Normal Loss",
                        message: String(format: "This loss was %.1f× your average losing trade", ratio)
                    )
                }
            }
        }

        if let ticker,
           ticker.previousTradeCount >= 10
        {
            let recent = peers
                .filter { TradeDetailComparisonScope.tickersMatch($0.symbol.ticker, ticker.ticker) }
                .sorted { $0.entryAt > $1.entryAt }
                .prefix(10)
            let recentWins = recent.filter { TradeDetailComparisonScope.netPnL(for: $0) > 0 }.count
            if recentWins >= 7 {
                return QuickInsight(
                    symbol: "🎯",
                    title: "Strong Ticker",
                    message: "You've won \(recentWins) of your last \(recent.count) \(ticker.ticker) trades"
                )
            }
        }

        if tradePnL > 0,
           let percentile = cohort?.pnlPercentile,
           percentile >= 90
        {
            return QuickInsight(
                symbol: "🔥",
                title: "Strong Trade",
                message: String(format: "Top %.0f%% of your trades by P&L", 100 - percentile)
            )
        }

        return nil
    }

    // MARK: - RPC mapping

    static func map(from payload: TradeDetailOwnerComparisonBootstrapV1.DataPayload, trade: Trade) -> Result {
        let cohort = payload.cohort.flatMap { wire -> CohortComparison? in
            guard wire.trade_count >= minCohortTrades else { return nil }
            var findings: [String] = []
            if let tradeRR = trade.riskReward, let avgRR = wire.avg_rr {
                let avgRRDecimal = Decimal(string: String(avgRR)) ?? 0
                let delta = NSDecimalNumber(decimal: tradeRR - avgRRDecimal).doubleValue
                if abs(delta) >= 0.3 {
                    findings.append(String(format: "%.1fR %@ your average trade", abs(delta), delta >= 0 ? "better than" : "worse than"))
                }
            }
            if let percentile = wire.pnl_percentile {
                if percentile >= 88, TradeDetailComparisonScope.netPnL(for: trade) > 0 {
                    findings.append(String(format: "Top %.0f%% of your trades by P&L", 100 - percentile))
                } else if percentile <= 12, TradeDetailComparisonScope.netPnL(for: trade) < 0 {
                    findings.append(String(format: "Bottom %.0f%% of your trades by P&L", percentile))
                }
            }
            if let holdPercent = wire.hold_shorter_than_percent {
                if holdPercent >= 60 {
                    findings.append(String(format: "Shorter hold time than %.0f%% of your trades", holdPercent))
                } else if holdPercent <= 25 {
                    findings.append(String(format: "Longer hold time than %.0f%% of your trades", 100 - holdPercent))
                }
            }
            return CohortComparison(
                avgPnL: wire.avg_pnl.map { Decimal(string: String($0)) ?? 0 } ?? 0,
                avgRR: wire.avg_rr.flatMap { Decimal(string: String($0)) },
                avgHoldSeconds: wire.avg_hold_seconds.map { Int($0.rounded()) },
                tradeCount: wire.trade_count,
                pnlPercentile: wire.pnl_percentile,
                rrPercentile: wire.rr_percentile,
                holdShorterThanPercent: wire.hold_shorter_than_percent,
                findings: Array(findings.prefix(3))
            )
        }

        let tickerHistory = payload.ticker_history.flatMap { wire -> TickerHistory? in
            let ticker = wire.ticker.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ticker.isEmpty else { return nil }
            let previousCount = wire.previous_trade_count
            let comparisonSentence: String
            if previousCount < minTickerTradesForComparison {
                comparisonSentence = "Not enough previous \(ticker) trades to compare yet."
            } else if trade.realizedPnL != nil {
                comparisonSentence =
                    "This trade performed better than \(wire.better_than_count) of your previous \(previousCount) \(ticker) trades."
            } else {
                comparisonSentence = "Not enough previous \(ticker) trades to compare yet."
            }
            return TickerHistory(
                ticker: ticker,
                previousTradeCount: previousCount,
                winRate: wire.win_rate.flatMap { Decimal(string: String($0)) },
                totalPnL: wire.total_pnl.flatMap { Decimal(string: String($0)) } ?? 0,
                profitFactor: wire.profit_factor.flatMap { Decimal(string: String($0)) },
                avgTradePnL: wire.avg_trade_pnl.flatMap { Decimal(string: String($0)) },
                comparisonSentence: comparisonSentence
            )
        }

        let insight = buildQuickInsightFromWire(trade: trade, cohort: cohort, ticker: tickerHistory, wire: payload)

        return Result(
            cohort: cohort,
            tickerHistory: tickerHistory,
            quickInsight: insight
        )
    }

    private static func buildQuickInsightFromWire(
        trade: Trade,
        cohort: CohortComparison?,
        ticker: TickerHistory?,
        wire: TradeDetailOwnerComparisonBootstrapV1.DataPayload
    ) -> QuickInsight? {
        if let tradeRR = trade.riskReward,
           let percentile = cohort?.rrPercentile,
           percentile >= 90,
           tradeRR > 0
        {
            return QuickInsight(
                symbol: "🔥",
                title: "Strong Trade",
                message: String(format: "Top %.0f%% of your trades by RR", 100 - percentile)
            )
        }

        let tradePnL = TradeDetailComparisonScope.netPnL(for: trade)
        if tradePnL < 0,
           let percentile = cohort?.pnlPercentile,
           percentile <= 12
        {
            return QuickInsight(
                symbol: "⚠️",
                title: "Larger Than Normal Loss",
                message: String(format: "Bottom %.0f%% of your trades by P&L", percentile)
            )
        }

        if let wireTicker = wire.ticker_history,
           wireTicker.previous_trade_count >= 10,
           wireTicker.recent_trade_count >= 7,
           wireTicker.recent_wins >= 7
        {
            return QuickInsight(
                symbol: "🎯",
                title: "Strong Ticker",
                message: "You've won \(wireTicker.recent_wins) of your last \(wireTicker.recent_trade_count) \(wireTicker.ticker) trades"
            )
        }

        if tradePnL > 0,
           let percentile = cohort?.pnlPercentile,
           percentile >= 90
        {
            return QuickInsight(
                symbol: "🔥",
                title: "Strong Trade",
                message: String(format: "Top %.0f%% of your trades by P&L", 100 - percentile)
            )
        }

        _ = ticker
        return nil
    }

    // MARK: - Helpers

    private static func averageRR(_ trades: [Trade]) -> Decimal? {
        let values = trades.compactMap(\.riskReward)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Decimal(values.count)
    }

    private static func averageHoldSeconds(_ trades: [Trade]) -> Int? {
        let values = trades.compactMap { holdSeconds(for: $0) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / values.count
    }

    private static func percentileRank(value: Decimal, in samples: [Decimal], higherIsBetter: Bool) -> Double {
        guard !samples.isEmpty else { return 0 }
        let below = samples.filter { $0 < value }.count
        let equal = samples.filter { $0 == value }.count
        let rank = Double(below) + Double(equal) * 0.5
        let percentile = rank / Double(samples.count) * 100
        return higherIsBetter ? percentile : 100 - percentile
    }

    private static func profitFactor(from pnls: [Decimal]) -> Decimal? {
        let grossWins = pnls.filter { $0 > 0 }.reduce(0, +)
        let grossLosses = pnls.filter { $0 < 0 }.reduce(0, +)
        guard grossLosses < 0 else { return nil }
        return grossWins / abs(grossLosses)
    }
}
