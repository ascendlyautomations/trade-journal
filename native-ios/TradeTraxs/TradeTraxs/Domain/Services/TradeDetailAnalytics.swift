import Foundation

/// Owner-only trade detail comparisons, RPC-first with scoped local fallback.
nonisolated enum TradeDetailAnalytics {
    static let minCohortTrades = 5
    static let minTickerTradesForComparison = 3

    enum ComparisonFilter: String, CaseIterable, Sendable, Identifiable {
        case all
        case accountMode
        case setup
        case session

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All"
            case .accountMode: return "Account/Mode"
            case .setup: return "Setup"
            case .session: return "Session"
            }
        }
    }

    struct SidePerformance: Equatable, Sendable {
        var tradeCount: Int
        var winRate: Decimal?
        var avgPnL: Decimal?
        var totalPnL: Decimal?
    }

    struct CohortComparison: Equatable, Sendable {
        var avgPnL: Decimal
        var winRate: Decimal?
        var avgTargetRR: Decimal?
        var avgRealizedRR: Decimal?
        var avgHoldSeconds: Int?
        var tradeCount: Int
        var pnlPercentile: Double?
        var targetRRPercentile: Double?
        var realizedRRPercentile: Double?
        var holdShorterThanPercent: Double?
        var long: SidePerformance?
        var short: SidePerformance?
        var findings: [String]

        /// Legacy alias for targeted R:R averages.
        var avgRR: Decimal? { avgTargetRR }
        /// Legacy alias for targeted R:R percentiles.
        var rrPercentile: Double? { targetRRPercentile }
    }

    struct CohortBundle: Equatable, Sendable {
        var all: CohortComparison?
        var accountMode: CohortComparison?
        var setup: CohortComparison?
        var session: CohortComparison?

        func cohort(for filter: ComparisonFilter) -> CohortComparison? {
            switch filter {
            case .all: return all
            case .accountMode: return accountMode
            case .setup: return setup
            case .session: return session
            }
        }
    }

    struct ComparisonFilterContext: Equatable, Sendable {
        var canUseAccountMode: Bool
        var canUseSetup: Bool
        var canUseSession: Bool

        func isAvailable(_ filter: ComparisonFilter) -> Bool {
            switch filter {
            case .all: return true
            case .accountMode: return canUseAccountMode
            case .setup: return canUseSetup
            case .session: return canUseSession
            }
        }
    }

    struct QuickInsight: Equatable, Sendable {
        var symbol: String
        var title: String
        var message: String
    }

    struct SessionPerformance: Equatable, Sendable {
        var session: String
        var tradeCount: Int
        var winRate: Decimal?
        var avgPnL: Decimal?
    }

    struct TickerWindowPerformance: Equatable, Sendable {
        var tradeCount: Int
        var winRate: Decimal?
        var totalPnL: Decimal
        var avgPnL: Decimal?
        var profitFactor: Decimal?
    }

    struct TickerHistory: Equatable, Sendable {
        var ticker: String
        var previousTradeCount: Int
        var winRate: Decimal?
        var totalPnL: Decimal
        var profitFactor: Decimal?
        var avgTradePnL: Decimal?
        var comparisonSentence: String
        var long: SidePerformance?
        var short: SidePerformance?
        var sessions: [SessionPerformance]
        var window30d: TickerWindowPerformance?
        var window90d: TickerWindowPerformance?
    }

    struct Result: Equatable, Sendable {
        var cohortBundle: CohortBundle?
        var comparisonFilterContext: ComparisonFilterContext
        var tickerHistory: TickerHistory?
        var quickInsight: QuickInsight?

        var cohort: CohortComparison? { cohortBundle?.all }
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
        let bundle = buildCohortBundle(trade: trade, peers: peers, accountModes: accountModes)
        let tickerHistory = buildTickerHistory(trade: trade, peers: peers)
        let insight = buildQuickInsight(
            trade: trade,
            peers: peers,
            cohort: bundle?.all,
            ticker: tickerHistory
        )
        let filterContext = buildFilterContext(trade: trade, accountModes: accountModes)
        return Result(
            cohortBundle: bundle,
            comparisonFilterContext: filterContext,
            tickerHistory: tickerHistory,
            quickInsight: insight
        )
    }

    static func map(
        from payload: TradeDetailOwnerComparisonBootstrapV1.DataPayload,
        trade: Trade,
        accountModes: [TradingAccountID: TradingAccountMode] = [:]
    ) -> Result {
        let bundle = mapCohortBundle(from: payload, trade: trade)
        let tickerHistory = payload.ticker_history.flatMap { mapTickerHistory(wire: $0, trade: trade) }
        let insight = buildQuickInsightFromWire(
            trade: trade,
            cohort: bundle?.all,
            ticker: tickerHistory,
            wire: payload
        )
        let filterContext = buildFilterContext(trade: trade, accountModes: accountModes)
        return Result(
            cohortBundle: bundle,
            comparisonFilterContext: filterContext,
            tickerHistory: tickerHistory,
            quickInsight: insight
        )
    }

    static func holdSeconds(for trade: Trade) -> Int? {
        if let seconds = trade.durationSeconds, seconds > 0 { return seconds }
        guard let exit = trade.exitAt else { return nil }
        return max(0, Int(exit.timeIntervalSince(trade.entryAt)))
    }

    static func resolvedTargetRR(for trade: Trade) -> Decimal? {
        trade.riskReward
    }

    static func resolvedRealizedRR(for trade: Trade) -> Decimal? {
        TradePointsAndRealizedRr.resolveRealizedRr(trade: trade)
    }

    // MARK: - Cohort bundle

    private static func buildCohortBundle(
        trade: Trade,
        peers: [Trade],
        accountModes: [TradingAccountID: TradingAccountMode]
    ) -> CohortBundle? {
        let all = buildCohortComparison(trade: trade, peers: peers)
        let accountMode = buildCohortComparison(
            trade: trade,
            peers: TradeDetailComparisonScope.filterPeers(
                peers,
                currentTrade: trade,
                filter: .accountMode,
                accountModes: accountModes
            )
        )
        let setup = buildCohortComparison(
            trade: trade,
            peers: TradeDetailComparisonScope.filterPeers(
                peers,
                currentTrade: trade,
                filter: .setup,
                accountModes: accountModes
            )
        )
        let session = buildCohortComparison(
            trade: trade,
            peers: TradeDetailComparisonScope.filterPeers(
                peers,
                currentTrade: trade,
                filter: .session,
                accountModes: accountModes
            )
        )

        if all == nil, accountMode == nil, setup == nil, session == nil {
            return nil
        }
        return CohortBundle(all: all, accountMode: accountMode, setup: setup, session: session)
    }

    private static func buildFilterContext(
        trade: Trade,
        accountModes: [TradingAccountID: TradingAccountMode]
    ) -> ComparisonFilterContext {
        ComparisonFilterContext(
            canUseAccountMode: trade.accountID != nil
                && ProfileStatisticsMetrics.resolveAccountMode(trade: trade, accountModes: accountModes) != nil,
            canUseSetup: TradeDetailComparisonScope.normalizedSetup(trade.strategy) != nil,
            canUseSession: TradingSessionLabel.canonicalLabel(fromStored: trade.sessionLabel) != nil
        )
    }

    private static func buildCohortComparison(trade: Trade, peers: [Trade]) -> CohortComparison? {
        guard peers.count >= minCohortTrades else { return nil }

        let pnls = peers.map(TradeDetailComparisonScope.netPnL)
        let avgPnL = pnls.reduce(0, +) / Decimal(pnls.count)
        let wins = pnls.filter { $0 > 0 }.count
        let winRate = Decimal(wins) / Decimal(pnls.count)
        let avgTargetRR = averageTargetRR(peers)
        let avgRealizedRR = averageRealizedRR(peers)
        let avgHold = averageHoldSeconds(peers)

        let pnlPercentile = trade.realizedPnL.map {
            percentileRank(value: $0.amount, in: pnls, higherIsBetter: true)
        }
        let targetRRPercentile = resolvedTargetRR(for: trade).flatMap { (rr: Decimal) -> Double? in
            let samples = peers.compactMap { resolvedTargetRR(for: $0) }
            guard samples.count >= minCohortTrades else { return nil }
            return percentileRank(value: rr, in: samples, higherIsBetter: true)
        }
        let realizedRRPercentile = resolvedRealizedRR(for: trade).flatMap { (rr: Decimal) -> Double? in
            let samples = peers.compactMap { resolvedRealizedRR(for: $0) }
            guard samples.count >= minCohortTrades else { return nil }
            return percentileRank(value: rr, in: samples, higherIsBetter: true)
        }

        var holdShorterThanPercent: Double?
        if let tradeHold = holdSeconds(for: trade) {
            let holdSamples = peers.compactMap { holdSeconds(for: $0) }
            if holdSamples.count >= minCohortTrades {
                let shorterCount = holdSamples.filter { $0 > tradeHold }.count
                holdShorterThanPercent = Double(shorterCount) / Double(holdSamples.count) * 100
            }
        }

        let longPeers = peers.filter { $0.side == .long }
        let shortPeers = peers.filter { $0.side == .short }
        let findings = buildFindings(
            trade: trade,
            avgTargetRR: avgTargetRR,
            avgRealizedRR: avgRealizedRR,
            pnlPercentile: pnlPercentile,
            targetRRPercentile: targetRRPercentile,
            realizedRRPercentile: realizedRRPercentile,
            holdShorterThanPercent: holdShorterThanPercent,
            long: sidePerformance(from: longPeers),
            short: sidePerformance(from: shortPeers)
        )

        return CohortComparison(
            avgPnL: avgPnL,
            winRate: winRate,
            avgTargetRR: avgTargetRR,
            avgRealizedRR: avgRealizedRR,
            avgHoldSeconds: avgHold,
            tradeCount: peers.count,
            pnlPercentile: pnlPercentile,
            targetRRPercentile: targetRRPercentile,
            realizedRRPercentile: realizedRRPercentile,
            holdShorterThanPercent: holdShorterThanPercent,
            long: sidePerformance(from: longPeers),
            short: sidePerformance(from: shortPeers),
            findings: findings
        )
    }

    private static func buildFindings(
        trade: Trade,
        avgTargetRR: Decimal?,
        avgRealizedRR: Decimal?,
        pnlPercentile: Double?,
        targetRRPercentile: Double?,
        realizedRRPercentile: Double?,
        holdShorterThanPercent: Double?,
        long: SidePerformance?,
        short: SidePerformance?
    ) -> [String] {
        var findings: [String] = []

        if let tradeTargetRR = resolvedTargetRR(for: trade),
           let avgTargetRR,
           avgTargetRR > 0
        {
            let delta = NSDecimalNumber(decimal: tradeTargetRR - avgTargetRR).doubleValue
            if abs(delta) >= 0.3 {
                findings.append(
                    "Target R:R was \(NumberDisplay.rMultiple(abs(delta), fractionDigits: 1)) \(delta >= 0 ? "above" : "below") this cohort average"
                )
            }
        }

        if let tradeRealizedRR = resolvedRealizedRR(for: trade),
           let avgRealizedRR,
           avgRealizedRR > 0
        {
            let delta = NSDecimalNumber(decimal: tradeRealizedRR - avgRealizedRR).doubleValue
            if abs(delta) >= 0.3 {
                findings.append(
                    "Realized R:R was \(NumberDisplay.rMultiple(abs(delta), fractionDigits: 1)) \(delta >= 0 ? "above" : "below") this cohort average"
                )
            }
        }

        if let percentile = pnlPercentile {
            let tradePnL = TradeDetailComparisonScope.netPnL(for: trade)
            if percentile >= 88, tradePnL > 0 {
                findings.append(
                    "Top \(NumberDisplay.percent(100 - percentile, minimumFractionDigits: 0, maximumFractionDigits: 0)) of this cohort by P&L"
                )
            } else if percentile <= 12, tradePnL < 0 {
                findings.append(
                    "Bottom \(NumberDisplay.percent(percentile, minimumFractionDigits: 0, maximumFractionDigits: 0)) of this cohort by P&L"
                )
            }
        }

        if let percentile = targetRRPercentile, percentile >= 85, resolvedTargetRR(for: trade) != nil {
            findings.append(
                "Target R:R beat \(NumberDisplay.percent(percentile, minimumFractionDigits: 0, maximumFractionDigits: 0)) of this cohort"
            )
        }

        if let percentile = realizedRRPercentile, percentile >= 85, resolvedRealizedRR(for: trade) != nil {
            findings.append(
                "Realized R:R beat \(NumberDisplay.percent(percentile, minimumFractionDigits: 0, maximumFractionDigits: 0)) of this cohort"
            )
        }

        if let holdPercent = holdShorterThanPercent {
            if holdPercent >= 60 {
                findings.append(
                    "Shorter hold than \(NumberDisplay.percent(holdPercent, minimumFractionDigits: 0, maximumFractionDigits: 0)) of this cohort"
                )
            } else if holdPercent <= 25 {
                findings.append(
                    "Longer hold than \(NumberDisplay.percent(100 - holdPercent, minimumFractionDigits: 0, maximumFractionDigits: 0)) of this cohort"
                )
            }
        }

        if let long,
           let short,
           long.tradeCount >= 3,
           short.tradeCount >= 3,
           let longAvg = long.avgPnL,
           let shortAvg = short.avgPnL,
           longAvg != shortAvg
        {
            let favorsLong = longAvg > shortAvg
            let sideLabel = favorsLong ? "Long" : "Short"
            let tradeSide = trade.side == .long ? "long" : "short"
            if (favorsLong && trade.side == .long) || (!favorsLong && trade.side == .short) {
                findings.append("\(sideLabel) trades average better P&L in this cohort — matches this \(tradeSide)")
            } else {
                findings.append("\(sideLabel) trades average better P&L in this cohort — opposite of this \(tradeSide)")
            }
        }

        return Array(findings.prefix(3))
    }

    // MARK: - Ticker

    private static func buildTickerHistory(trade: Trade, peers: [Trade]) -> TickerHistory? {
        let ticker = TradeDetailComparisonScope.normalizedTicker(trade.symbol.ticker)
        guard !ticker.isEmpty else { return nil }

        let sameTicker = peers.filter {
            TradeDetailComparisonScope.tickersMatch($0.symbol.ticker, ticker)
        }
        return assembleTickerHistory(trade: trade, ticker: ticker, sameTicker: sameTicker)
    }

    private static func assembleTickerHistory(trade: Trade, ticker: String, sameTicker: [Trade]) -> TickerHistory {
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

        let longPeers = sameTicker.filter { $0.side == .long }
        let shortPeers = sameTicker.filter { $0.side == .short }

        let sessions = sessionBreakdown(for: sameTicker)
        let window30d = windowPerformance(for: sameTicker, days: 30)
        let window90d = windowPerformance(for: sameTicker, days: 90)

        return TickerHistory(
            ticker: ticker,
            previousTradeCount: previousCount,
            winRate: winRate,
            totalPnL: totalPnL,
            profitFactor: profitFactor,
            avgTradePnL: avgTradePnL,
            comparisonSentence: comparisonSentence,
            long: sidePerformance(from: longPeers, includeTotal: true),
            short: sidePerformance(from: shortPeers, includeTotal: true),
            sessions: sessions,
            window30d: window30d,
            window90d: window90d
        )
    }

    private static func sessionBreakdown(for trades: [Trade]) -> [SessionPerformance] {
        var buckets: [String: [Trade]] = [:]
        for trade in trades {
            guard let label = TradingSessionLabel.canonicalLabel(fromStored: trade.sessionLabel) else { continue }
            buckets[label, default: []].append(trade)
        }
        return buckets
            .map { (session, rows) in
                let pnls = rows.map(TradeDetailComparisonScope.netPnL)
                let wins = pnls.filter { $0 > 0 }.count
                let winRate = Decimal(wins) / Decimal(pnls.count)
                let avg = pnls.reduce(0, +) / Decimal(pnls.count)
                return SessionPerformance(
                    session: session,
                    tradeCount: rows.count,
                    winRate: winRate,
                    avgPnL: avg
                )
            }
            .sorted { lhs, rhs in
                if lhs.tradeCount != rhs.tradeCount { return lhs.tradeCount > rhs.tradeCount }
                return lhs.session < rhs.session
            }
            .prefix(4)
            .map { $0 }
    }

    private static func windowPerformance(for trades: [Trade], days: Int) -> TickerWindowPerformance? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        let windowTrades = trades.filter { $0.entryAt >= cutoff }
        guard !windowTrades.isEmpty else { return nil }
        let pnls = windowTrades.map(TradeDetailComparisonScope.netPnL)
        let wins = pnls.filter { $0 > 0 }.count
        let total = pnls.reduce(0, +)
        return TickerWindowPerformance(
            tradeCount: windowTrades.count,
            winRate: Decimal(wins) / Decimal(pnls.count),
            totalPnL: total,
            avgPnL: total / Decimal(pnls.count),
            profitFactor: profitFactor(from: pnls)
        )
    }

    // MARK: - Quick insight

    private static func buildQuickInsight(
        trade: Trade,
        peers: [Trade],
        cohort: CohortComparison?,
        ticker: TickerHistory?
    ) -> QuickInsight? {
        if let tradeRR = resolvedTargetRR(for: trade),
           let percentile = cohort?.targetRRPercentile,
           percentile >= 90,
           tradeRR > 0
        {
            return QuickInsight(
                symbol: "🔥",
                title: "Strong Trade",
                message: "Top \(NumberDisplay.percent(100 - percentile, minimumFractionDigits: 0, maximumFractionDigits: 0)) of your trades by target R:R"
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
                        message: "This loss was \(NumberDisplay.multiple(ratio, fractionDigits: 1)) your average losing trade"
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
                message: "Top \(NumberDisplay.percent(100 - percentile, minimumFractionDigits: 0, maximumFractionDigits: 0)) of your trades by P&L"
            )
        }

        return nil
    }

    // MARK: - RPC mapping

    private static func mapCohortBundle(
        from payload: TradeDetailOwnerComparisonBootstrapV1.DataPayload,
        trade: Trade
    ) -> CohortBundle? {
        let legacyAll = payload.cohort.flatMap { mapCohort(wire: $0, trade: trade) }

        if let wireBundle = payload.cohorts {
            let bundle = CohortBundle(
                all: wireBundle.all.flatMap { mapCohort(wire: $0, trade: trade) } ?? legacyAll,
                accountMode: wireBundle.account_mode.flatMap { mapCohort(wire: $0, trade: trade) },
                setup: wireBundle.setup.flatMap { mapCohort(wire: $0, trade: trade) },
                session: wireBundle.session.flatMap { mapCohort(wire: $0, trade: trade) }
            )
            if bundle.all != nil
                || bundle.accountMode != nil
                || bundle.setup != nil
                || bundle.session != nil
            {
                return bundle
            }
            return legacyAll.map {
                CohortBundle(all: $0, accountMode: nil, setup: nil, session: nil)
            }
        }

        guard let legacyAll else { return nil }
        return CohortBundle(all: legacyAll, accountMode: nil, setup: nil, session: nil)
    }

    private static func mapCohort(
        wire: TradeDetailOwnerComparisonBootstrapV1.CohortWire,
        trade: Trade
    ) -> CohortComparison? {
        guard wire.trade_count >= minCohortTrades else { return nil }

        let avgTarget = wire.avg_target_rr ?? wire.avg_rr
        let avgTargetDecimal = avgTarget.flatMap { Decimal(string: String($0)) }
        let avgRealizedDecimal = wire.avg_realized_rr.flatMap { Decimal(string: String($0)) }
        let long = wire.long.map { mapSidePerformance($0) }
        let short = wire.short.map { mapSidePerformance($0) }

        let findings = buildFindings(
            trade: trade,
            avgTargetRR: avgTargetDecimal,
            avgRealizedRR: avgRealizedDecimal,
            pnlPercentile: wire.pnl_percentile,
            targetRRPercentile: wire.target_rr_percentile ?? wire.rr_percentile,
            realizedRRPercentile: wire.realized_rr_percentile,
            holdShorterThanPercent: wire.hold_shorter_than_percent,
            long: long,
            short: short
        )

        return CohortComparison(
            avgPnL: wire.avg_pnl.map { Decimal(string: String($0)) ?? 0 } ?? 0,
            winRate: wire.win_rate.flatMap { Decimal(string: String($0)) },
            avgTargetRR: avgTargetDecimal,
            avgRealizedRR: avgRealizedDecimal,
            avgHoldSeconds: wire.avg_hold_seconds.map { Int($0.rounded()) },
            tradeCount: wire.trade_count,
            pnlPercentile: wire.pnl_percentile,
            targetRRPercentile: wire.target_rr_percentile ?? wire.rr_percentile,
            realizedRRPercentile: wire.realized_rr_percentile,
            holdShorterThanPercent: wire.hold_shorter_than_percent,
            long: long,
            short: short,
            findings: findings
        )
    }

    private static func mapTickerHistory(
        wire: TradeDetailOwnerComparisonBootstrapV1.TickerHistoryWire,
        trade: Trade
    ) -> TickerHistory? {
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
            comparisonSentence: comparisonSentence,
            long: wire.long.map { mapSidePerformance($0) },
            short: wire.short.map { mapSidePerformance($0) },
            sessions: (wire.sessions ?? []).map { slice in
                SessionPerformance(
                    session: slice.session,
                    tradeCount: slice.trade_count,
                    winRate: slice.win_rate.flatMap { Decimal(string: String($0)) },
                    avgPnL: slice.avg_pnl.flatMap { Decimal(string: String($0)) }
                )
            },
            window30d: wire.window_30d.flatMap { mapTickerWindow($0) },
            window90d: wire.window_90d.flatMap { mapTickerWindow($0) }
        )
    }

    private static func mapSidePerformance(
        _ wire: TradeDetailOwnerComparisonBootstrapV1.SideSliceWire
    ) -> SidePerformance {
        SidePerformance(
            tradeCount: wire.trade_count,
            winRate: wire.win_rate.flatMap { Decimal(string: String($0)) },
            avgPnL: wire.avg_pnl.flatMap { Decimal(string: String($0)) },
            totalPnL: wire.total_pnl.flatMap { Decimal(string: String($0)) }
        )
    }

    private static func mapTickerWindow(
        _ wire: TradeDetailOwnerComparisonBootstrapV1.TickerWindowWire
    ) -> TickerWindowPerformance? {
        guard wire.trade_count > 0 else { return nil }
        return TickerWindowPerformance(
            tradeCount: wire.trade_count,
            winRate: wire.win_rate.flatMap { Decimal(string: String($0)) },
            totalPnL: wire.total_pnl.flatMap { Decimal(string: String($0)) } ?? 0,
            avgPnL: wire.avg_pnl.flatMap { Decimal(string: String($0)) },
            profitFactor: wire.profit_factor.flatMap { Decimal(string: String($0)) }
        )
    }

    private static func buildQuickInsightFromWire(
        trade: Trade,
        cohort: CohortComparison?,
        ticker: TickerHistory?,
        wire: TradeDetailOwnerComparisonBootstrapV1.DataPayload
    ) -> QuickInsight? {
        if let tradeRR = resolvedTargetRR(for: trade),
           let percentile = cohort?.targetRRPercentile,
           percentile >= 90,
           tradeRR > 0
        {
            return QuickInsight(
                symbol: "🔥",
                title: "Strong Trade",
                message: "Top \(NumberDisplay.percent(100 - percentile, minimumFractionDigits: 0, maximumFractionDigits: 0)) of your trades by target R:R"
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
                message: "Bottom \(NumberDisplay.percent(percentile, minimumFractionDigits: 0, maximumFractionDigits: 0)) of your trades by P&L"
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
                message: "Top \(NumberDisplay.percent(100 - percentile, minimumFractionDigits: 0, maximumFractionDigits: 0)) of your trades by P&L"
            )
        }

        _ = ticker
        return nil
    }

    // MARK: - Helpers

    private static func sidePerformance(from peers: [Trade], includeTotal: Bool = false) -> SidePerformance? {
        guard !peers.isEmpty else { return nil }
        let pnls = peers.map(TradeDetailComparisonScope.netPnL)
        let wins = pnls.filter { $0 > 0 }.count
        let total = pnls.reduce(0, +)
        return SidePerformance(
            tradeCount: peers.count,
            winRate: Decimal(wins) / Decimal(pnls.count),
            avgPnL: total / Decimal(pnls.count),
            totalPnL: includeTotal ? total : nil
        )
    }

    private static func averageTargetRR(_ trades: [Trade]) -> Decimal? {
        let values = trades.compactMap { resolvedTargetRR(for: $0) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Decimal(values.count)
    }

    private static func averageRealizedRR(_ trades: [Trade]) -> Decimal? {
        let values = trades.compactMap { resolvedRealizedRR(for: $0) }
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