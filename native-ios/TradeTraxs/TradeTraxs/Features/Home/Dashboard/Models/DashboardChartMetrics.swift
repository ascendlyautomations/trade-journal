import Foundation

/// Presentation aggregations for the native Dashboard.
///
/// Formulas mirror web `useDashboardAnalytics` / `dashboardMaxDrawdown` /
/// `dashboardHoldTimeStats` / session buckets, no repository changes.
nonisolated enum DashboardChartMetrics {
    struct Input: Sendable, Equatable {
        var trade: Trade
        var accountType: String?
    }

    static func resolvedAccountMode(for input: Input) -> TradingAccountMode? {
        DashboardScopeFilterSupport.profileStatisticsEffectiveMode(for: input.trade)
    }

    struct Summary: Sendable, Equatable {
        var netPnL: Decimal
        var winRate: Decimal?
        var profitFactor: Decimal?
        var payouts: Decimal?
        var expectancy: Decimal?
        var averageRR: Decimal?
        var averageMaxRrReached: Decimal?
        var rrTargetAnalysis: DashboardRrTargetAnalysis
        var tradeCount: Int
        var winCount: Int
        var lossCount: Int
        var avgWin: Decimal?
        var avgLoss: Decimal?
        var bestTrade: Decimal?
        var biggestLoss: Decimal?
        var maxDrawdown: Decimal
        var currentEquity: Decimal
        var equityData: [ProfileStatisticsMetrics.EquityPoint]
        var sessions: [ProfileStatisticsMetrics.SessionRow]
        var weekdays: [DashboardBarPoint]
        var hours: [DashboardBarPoint]
        var longShort: [DashboardBarPoint]
        var longTradeCount: Int
        var shortTradeCount: Int
        var winLoss: [DashboardWinLossPoint]
        var holdTime: [DashboardHoldTimeRow]
        /// Presentation buckets for hold-duration histogram (same durations as ``holdTime``).
        var holdTimeHistogram: [DashboardHistogramBucket]
        /// Underwater series derived from ``equityData`` (peak − equity as negative depth).
        var drawdownSeries: [DashboardDrawdownPoint]
        /// Full Mon–Sun weekday P&L for heatmap (same formula as ``weekdays``).
        var weekdayHeatmap: [DashboardBarPoint]
        /// Full 0–23 hour P&L for heatmap (same formula as ``hours``).
        var hourHeatmap: [DashboardBarPoint]
        var insights: [DashboardInsightItem]
        var sessionPerformance: [DashboardSessionPerformanceRow]
        var symbolPerformance: [DashboardSymbolPerformanceRow]
        var dailyPerformance: DashboardDailyPerformanceSnapshot?
        var streaks: DashboardStreakSnapshot?
        var hourHighlights: DashboardHourHighlights?
        var longShortComparison: DashboardLongShortComparison?
        var holdExtremes: [DashboardHoldExtremeSnapshot]
        var strategyHighlights: DashboardStrategyHighlights?
    }

    static func compute(
        from inputs: [Input],
        accountFilter: DashboardAccountFilter,
        dateRange: DashboardDateRange,
        payoutTotal: Decimal?,
        now: Date = Date()
    ) -> Summary {
        compute(
            from: inputs,
            scope: DashboardClientScopeFilter(
                accountFilter: accountFilter,
                dateRange: dateRange,
                customInterval: nil,
                accountMode: .all,
                showPublicOnly: false
            ),
            payoutTotal: payoutTotal,
            now: now
        )
    }

    static func compute(
        from inputs: [Input],
        scope: DashboardClientScopeFilter,
        payoutTotal: Decimal?,
        now: Date = Date()
    ) -> Summary {
        compute(
            from: inputs,
            accountFilter: scope.accountFilter,
            accountMode: scope.accountMode,
            linkedAccountModes: scope.linkedAccountModes,
            copyTradingGroups: scope.copyTradingGroups,
            interval: scope.customInterval,
            dateRange: scope.customInterval == nil ? scope.dateRange : nil,
            showPublicOnly: scope.showPublicOnly,
            payoutTotal: payoutTotal,
            now: now
        )
    }

    /// Interval-scoped analytics, used by yearly/monthly Performance Reports.
    static func compute(
        from inputs: [Input],
        accountFilter: DashboardAccountFilter,
        accountMode: ProfileStatisticsMetrics.Mode = .all,
        interval: DateInterval,
        payoutTotal: Decimal? = nil,
        now: Date = Date()
    ) -> Summary {
        compute(
            from: inputs,
            accountFilter: accountFilter,
            accountMode: accountMode,
            linkedAccountModes: [:],
            interval: interval,
            dateRange: nil,
            showPublicOnly: false,
            payoutTotal: payoutTotal,
            now: now
        )
    }

    private static func compute(
        from inputs: [Input],
        accountFilter: DashboardAccountFilter,
        accountMode: ProfileStatisticsMetrics.Mode,
        linkedAccountModes: [TradingAccountID: TradingAccountMode],
        copyTradingGroups: [CopyTradingGroup] = [],
        interval: DateInterval?,
        dateRange: DashboardDateRange?,
        showPublicOnly: Bool,
        payoutTotal: Decimal?,
        now: Date
    ) -> Summary {
        let filtered = filter(
            inputs,
            accountFilter: accountFilter,
            accountMode: accountMode,
            linkedAccountModes: linkedAccountModes,
            copyTradingGroups: copyTradingGroups,
            interval: interval,
            dateRange: dateRange,
            showPublicOnly: showPublicOnly,
            now: now
        )
        var trades = filtered.map(\.trade)
        if DashboardAccountFilterCopyTradingSupport.shouldDedupeCopyMetrics(for: accountFilter) {
            trades = DashboardAccountFilterCopyTradingSupport.dedupeCopyTradedTradesForMetrics(trades)
        }

        let pnlValues = trades.compactMap(\.realizedPnL?.amount)
        let wins = pnlValues.filter { $0 > 0 }
        let losses = pnlValues.filter { $0 < 0 }
        let tradeCount = trades.count
        let winCount = wins.count
        let lossCount = losses.count
        let netPnL = pnlValues.reduce(Decimal(0), +)
        let pricedCount = pnlValues.count

        let winRate: Decimal? = pricedCount > 0 ? Decimal(winCount) / Decimal(pricedCount) : nil
        let grossWins = wins.reduce(Decimal(0), +)
        let grossLosses = losses.reduce(Decimal(0), +)
        let profitFactor: Decimal? = grossLosses < 0 ? grossWins / abs(grossLosses) : nil

        let avgWin: Decimal? = winCount > 0 ? grossWins / Decimal(winCount) : nil
        let avgLossAbs: Decimal? = lossCount > 0 ? abs(grossLosses) / Decimal(lossCount) : nil
        let lossRate: Decimal = pricedCount > 0 ? Decimal(lossCount) / Decimal(pricedCount) : 0
        let winRateFrac: Decimal = winRate ?? 0
        let expectancy: Decimal? = {
            guard pricedCount > 0 else { return nil }
            return winRateFrac * (avgWin ?? 0) - lossRate * (avgLossAbs ?? 0)
        }()

        let averageRR = TradePointsAndRealizedRr.averageTargetedRr(trades: trades)

        var maxRrSum = Decimal(0)
        var maxRrCount = 0
        for trade in trades {
            guard let maxRr = trade.maxRrReached else { continue }
            maxRrSum += maxRr
            maxRrCount += 1
        }
        let averageMaxRrReached: Decimal? = maxRrCount > 0 ? maxRrSum / Decimal(maxRrCount) : nil

        let statsInputs = filtered.map {
            ProfileStatisticsMetrics.TradeInput(
                pnl: $0.trade.realizedPnL?.amount,
                createdAt: $0.trade.exitAt ?? $0.trade.entryAt,
                isLong: $0.trade.side == .long,
                session: $0.trade.sessionLabel,
                accountMode: resolvedAccountMode(for: $0),
                sortKey: $0.trade.id.rawValue
            )
        }
        let profileStats = ProfileStatisticsMetrics.compute(from: statsInputs, selectedMode: .all)

        let longCount = trades.filter { $0.side == .long }.count
        let shortCount = tradeCount - longCount
        let holdDurations = holdDurations(trades)

        return Summary(
            netPnL: netPnL,
            winRate: winRate,
            profitFactor: profitFactor,
            payouts: payoutTotal,
            expectancy: expectancy,
            averageRR: averageRR,
            averageMaxRrReached: averageMaxRrReached,
            rrTargetAnalysis: DashboardRrTargetAnalysis.compute(from: trades),
            tradeCount: tradeCount,
            winCount: winCount,
            lossCount: lossCount,
            avgWin: avgWin,
            avgLoss: avgLossAbs.map { -$0 },
            bestTrade: wins.max(),
            biggestLoss: losses.min(),
            maxDrawdown: maxDrawdown(trades),
            currentEquity: profileStats.currentEquity,
            equityData: profileStats.equityData,
            sessions: profileStats.sessionBreakdown,
            weekdays: weekdayBars(trades),
            hours: hourBars(trades),
            longShort: longShortBars(trades),
            longTradeCount: longCount,
            shortTradeCount: shortCount,
            winLoss: [
                DashboardWinLossPoint(label: "Wins", count: winCount),
                DashboardWinLossPoint(label: "Losses", count: lossCount),
            ],
            holdTime: holdTimeRows(from: holdDurations),
            holdTimeHistogram: holdTimeHistogram(from: trades),
            drawdownSeries: drawdownSeries(from: profileStats.equityData),
            weekdayHeatmap: weekdayHeatmapBars(trades),
            hourHeatmap: hourHeatmapBars(trades),
            insights: insightItems(trades: trades, sessions: profileStats.sessionBreakdown),
            sessionPerformance: localSessionPerformance(trades),
            symbolPerformance: localSymbolPerformance(trades),
            dailyPerformance: localDailyPerformance(trades),
            streaks: localStreaks(trades),
            hourHighlights: localHourHighlights(trades),
            longShortComparison: localLongShortComparison(trades),
            holdExtremes: localHoldExtremes(trades),
            strategyHighlights: localStrategyHighlights(trades)
        )
    }

    /// Filtered trades for the active dashboard scope, shared with psychology analytics.
    static func filteredTrades(
        from inputs: [Input],
        accountFilter: DashboardAccountFilter,
        dateRange: DashboardDateRange,
        now: Date = Date()
    ) -> [Trade] {
        filteredTrades(
            from: inputs,
            scope: DashboardClientScopeFilter(
                accountFilter: accountFilter,
                dateRange: dateRange,
                customInterval: nil,
                accountMode: .all,
                showPublicOnly: false
            ),
            now: now
        )
    }

    static func filteredTrades(
        from inputs: [Input],
        scope: DashboardClientScopeFilter,
        now: Date = Date()
    ) -> [Trade] {
        let trades = filter(
            inputs,
            accountFilter: scope.accountFilter,
            accountMode: scope.accountMode,
            linkedAccountModes: scope.linkedAccountModes,
            copyTradingGroups: scope.copyTradingGroups,
            interval: scope.customInterval,
            dateRange: scope.customInterval == nil ? scope.dateRange : nil,
            showPublicOnly: scope.showPublicOnly,
            now: now
        ).map(\.trade)
        if DashboardAccountFilterCopyTradingSupport.shouldDedupeCopyMetrics(for: scope.accountFilter) {
            return DashboardAccountFilterCopyTradingSupport.dedupeCopyTradedTradesForMetrics(trades)
        }
        return trades
    }

    /// Filtered trades for an explicit interval, shared with Performance Reports.
    static func filteredTrades(
        from inputs: [Input],
        accountFilter: DashboardAccountFilter,
        accountMode: ProfileStatisticsMetrics.Mode = .all,
        interval: DateInterval,
        now: Date = Date()
    ) -> [Trade] {
        filter(
            inputs,
            accountFilter: accountFilter,
            accountMode: accountMode,
            linkedAccountModes: [:],
            interval: interval,
            dateRange: nil,
            showPublicOnly: false,
            now: now
        ).map(\.trade)
    }

    // MARK: - Filter (web time + account)

    private static func filter(
        _ inputs: [Input],
        accountFilter: DashboardAccountFilter,
        dateRange: DashboardDateRange,
        now: Date
    ) -> [Input] {
        filter(
            inputs,
            accountFilter: accountFilter,
            accountMode: .all,
            linkedAccountModes: [:],
            interval: nil,
            dateRange: dateRange,
            showPublicOnly: false,
            now: now
        )
    }

    private static func filter(
        _ inputs: [Input],
        accountFilter: DashboardAccountFilter,
        accountMode selectedMode: ProfileStatisticsMetrics.Mode,
        linkedAccountModes: [TradingAccountID: TradingAccountMode],
        copyTradingGroups: [CopyTradingGroup] = [],
        interval: DateInterval?,
        dateRange: DashboardDateRange?,
        showPublicOnly: Bool,
        now: Date
    ) -> [Input] {
        let scoped = inputs.filter { input in
            let trade = input.trade

            guard DashboardAccountFilterCopyTradingSupport.matchesTrade(
                trade,
                filter: accountFilter,
                copyGroups: copyTradingGroups
            ) else { return false }

            guard DashboardScopeFilterSupport.matchesProfileStatisticsAccountModeFilter(
                trade: trade,
                linkedAccountModes: linkedAccountModes,
                selected: selectedMode
            ) else { return false }

            let stamp = DashboardScopeFilterSupport.dashboardTradeFilterDate(for: trade)
            if let interval {
                return stamp >= interval.start && stamp <= interval.end
            }
            if let dateRange {
                return dateRange.contains(stamp, now: now)
            }
            return true
        }
        return applyPublicVisibilityFilter(scoped, showPublicOnly: showPublicOnly)
    }

    /// Profile → Stats public universe, `is_public` only (matches ``ProfileStatisticsTradeLoader``).
    private static func applyPublicVisibilityFilter(_ inputs: [Input], showPublicOnly: Bool) -> [Input] {
        guard showPublicOnly else { return inputs }
        return inputs.filter { DashboardScopeFilterSupport.isProfileStatisticsPublicTrade($0.trade) }
    }

    // MARK: - Drawdown (web computeMaxDrawdown)

    private static func maxDrawdown(_ trades: [Trade]) -> Decimal {
        let chronological = trades.sorted {
            ($0.exitAt ?? $0.entryAt) < ($1.exitAt ?? $1.entryAt)
        }
        var running: Decimal = 0
        var peak: Decimal = 0
        var maxDD: Decimal = 0
        for trade in chronological {
            guard let amount = trade.realizedPnL?.amount else { continue }
            running += amount
            if running > peak { peak = running }
            let drawdown = peak - running
            if drawdown > maxDD { maxDD = drawdown }
        }
        return maxDD
    }

    // MARK: - Weekdays / Hours

    private static func futuresWeekday(_ trade: Trade) -> Int? {
        guard let key = DashboardTradingDayKey.key(for: trade) else { return nil }
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let calendar = TradingReportPeriods.eastern
        guard let date = calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: parts[0],
            month: parts[1],
            day: parts[2],
            hour: 12
        )) else { return nil }
        return calendar.component(.weekday, from: date)
    }

    private static func weekdayBars(_ trades: [Trade]) -> [DashboardBarPoint] {
        let labels = ["Mon", "Tue", "Wed", "Thu", "Fri"]
        var map: [Int: Decimal] = [:]
        for trade in trades {
            guard let weekday = futuresWeekday(trade) else { continue }
            // Map to Mon=0 ... Fri=4
            let index: Int?
            switch weekday {
            case 2: index = 0
            case 3: index = 1
            case 4: index = 2
            case 5: index = 3
            case 6: index = 4
            default: index = nil
            }
            guard let index else { continue }
            guard let amount = trade.realizedPnL?.amount else { continue }
            map[index, default: 0] += amount
        }
        return labels.enumerated().map { offset, label in
            DashboardBarPoint(
                label: label,
                value: NSDecimalNumber(decimal: map[offset] ?? 0).doubleValue
            )
        }
    }

    private static func hourBars(_ trades: [Trade]) -> [DashboardBarPoint] {
        var map: [Int: Decimal] = [:]
        let calendar = TradingReportPeriods.eastern
        for trade in trades {
            let hour = calendar.component(.hour, from: trade.entryAt)
            guard let amount = trade.realizedPnL?.amount else { continue }
            map[hour, default: 0] += amount
        }
        // Show hours that have activity, keep chronological.
        let active = map.keys.sorted()
        guard active.count > 1 else {
            return active.map {
                DashboardBarPoint(
                    label: hourLabel($0),
                    value: NSDecimalNumber(decimal: map[$0] ?? 0).doubleValue
                )
            }
        }
        return active.map {
            DashboardBarPoint(
                label: hourLabel($0),
                value: NSDecimalNumber(decimal: map[$0] ?? 0).doubleValue
            )
        }
    }

    private static func hourLabel(_ hour: Int) -> String {
        String(format: "%02d", hour)
    }

    private static func longShortBars(_ trades: [Trade]) -> [DashboardBarPoint] {
        let longPnL = trades.filter { $0.side == .long }.compactMap(\.realizedPnL?.amount).reduce(Decimal(0), +)
        let shortPnL = trades.filter { $0.side == .short }.compactMap(\.realizedPnL?.amount).reduce(Decimal(0), +)
        return [
            DashboardBarPoint(
                label: "Long",
                value: NSDecimalNumber(decimal: longPnL).doubleValue
            ),
            DashboardBarPoint(
                label: "Short",
                value: NSDecimalNumber(decimal: shortPnL).doubleValue
            ),
        ]
    }

    // MARK: - Hold time (web resolveTradeDurationSeconds)

    private struct HoldDurations: Sendable {
        var all: [TimeInterval]
        var win: [TimeInterval]
        var loss: [TimeInterval]
    }

    private static func holdDurations(_ trades: [Trade]) -> HoldDurations {
        var all: [TimeInterval] = []
        var win: [TimeInterval] = []
        var loss: [TimeInterval] = []
        for trade in trades {
            guard let exit = trade.exitAt else { continue }
            let seconds = exit.timeIntervalSince(trade.entryAt)
            guard seconds > 0 else { continue }
            all.append(seconds)
            if let pnl = trade.realizedPnL?.amount {
                if pnl > 0 { win.append(seconds) }
                else if pnl < 0 { loss.append(seconds) }
            }
        }
        return HoldDurations(all: all, win: win, loss: loss)
    }

    private static func holdTimeRows(from durations: HoldDurations) -> [DashboardHoldTimeRow] {
        guard !durations.all.isEmpty else { return [] }
        return [
            DashboardHoldTimeRow(label: "Avg Hold", value: formatDuration(average(durations.all))),
            DashboardHoldTimeRow(label: "Avg Winner", value: formatDuration(average(durations.win))),
            DashboardHoldTimeRow(label: "Avg Loser", value: formatDuration(average(durations.loss))),
        ]
    }

    private static func holdTimeHistogram(from trades: [Trade]) -> [DashboardHistogramBucket] {
        let defs: [(String, Range<TimeInterval>)] = [
            ("<5m", 0..<300),
            ("5–15m", 300..<900),
            ("15–60m", 900..<3_600),
            ("1–4h", 3_600..<14_400),
            ("4h+", 14_400..<TimeInterval.greatestFiniteMagnitude),
        ]
        struct BucketScratch {
            var count = 0
            var totalPnL = 0.0
        }
        var scratch = [String: BucketScratch]()
        for label in defs.map(\.0) {
            scratch[label] = BucketScratch()
        }

        for trade in trades {
            guard let exit = trade.exitAt else { continue }
            let duration = exit.timeIntervalSince(trade.entryAt)
            guard duration > 0 else { continue }
            guard let def = defs.first(where: { $0.1.contains(duration) }) else { continue }
            let pnl = NSDecimalNumber(decimal: trade.realizedPnL?.amount ?? 0).doubleValue
            var bucket = scratch[def.0] ?? BucketScratch()
            bucket.count += 1
            bucket.totalPnL += pnl
            scratch[def.0] = bucket
        }

        return defs.map { label, _ in
            let bucket = scratch[label] ?? BucketScratch()
            return DashboardHistogramBucket(
                label: label,
                count: bucket.count,
                totalNetPnL: bucket.totalPnL
            )
        }
    }

    private static func average(_ values: [TimeInterval]) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func formatDuration(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "–" }
        let total = Int(seconds.rounded(.down))
        return TradeHoldDuration.formatSeconds(total) ?? "–"
    }

    // MARK: - Drawdown series (presentation from equity path)

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

    // MARK: - Heatmap pads (same P&L formulas, full domain)

    private static func weekdayHeatmapBars(_ trades: [Trade]) -> [DashboardBarPoint] {
        let labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        var map: [Int: Decimal] = [:]
        for trade in trades {
            guard let weekday = futuresWeekday(trade) else { continue }
            let index: Int
            switch weekday {
            case 2: index = 0
            case 3: index = 1
            case 4: index = 2
            case 5: index = 3
            case 6: index = 4
            case 7: index = 5
            case 1: index = 6
            default: continue
            }
            guard let amount = trade.realizedPnL?.amount else { continue }
            map[index, default: 0] += amount
        }
        return labels.enumerated().map { offset, label in
            DashboardBarPoint(
                label: label,
                value: NSDecimalNumber(decimal: map[offset] ?? 0).doubleValue
            )
        }
    }

    private static func hourHeatmapBars(_ trades: [Trade]) -> [DashboardBarPoint] {
        var map: [Int: Decimal] = [:]
        let calendar = TradingReportPeriods.eastern
        for trade in trades {
            let hour = calendar.component(.hour, from: trade.entryAt)
            guard let amount = trade.realizedPnL?.amount else { continue }
            map[hour, default: 0] += amount
        }
        return (0..<24).map { hour in
            DashboardBarPoint(
                label: hourLabel(hour),
                value: NSDecimalNumber(decimal: map[hour] ?? 0).doubleValue
            )
        }
    }

    // MARK: - Insights

    private static func insightItems(
        trades: [Trade],
        sessions: [ProfileStatisticsMetrics.SessionRow]
    ) -> [DashboardInsightItem] {
        var items: [DashboardInsightItem] = []
        if let bestSession = sessions.max(by: { $0.pct < $1.pct }), bestSession.pct >= 1 {
            items.append(
                DashboardInsightItem(
                    id: "session",
                    title: "Protect your best session",
                    body: "Most of your tagged volume lands in \(bestSession.label) (\(Int(bestSession.pct.rounded()))%). Review those setups first, that's where your process is already concentrated.",
                    kind: .session
                )
            )
        }

        var symbolPnL: [String: (pnl: Decimal, count: Int)] = [:]
        for trade in trades {
            guard let amount = trade.realizedPnL?.amount else { continue }
            let key = trade.symbol.ticker
            let current = symbolPnL[key] ?? (0, 0)
            symbolPnL[key] = (current.pnl + amount, current.count + 1)
        }
        let qualifiedSymbols = symbolPnL.filter { $0.value.count >= 5 }
        if qualifiedSymbols.count >= 2,
           let best = qualifiedSymbols.max(by: {
               ($0.value.pnl / Decimal($0.value.count)) < ($1.value.pnl / Decimal($1.value.count))
           }) {
            let avg = best.value.pnl / Decimal(best.value.count)
            if avg > 0 {
                items.append(
                    DashboardInsightItem(
                        id: "symbol",
                        title: "Strongest average symbol",
                        body: "\(best.key) averaged \(money(avg)) across \(best.value.count) priced trades.",
                        kind: .symbol
                    )
                )
            }
        }

        let longCount = trades.filter { $0.side == .long }.count
        let shortCount = trades.count - longCount
        if trades.count >= 5 {
            let edge = longCount >= shortCount ? "long" : "short"
            let majority = max(longCount, shortCount)
            items.append(
                DashboardInsightItem(
                    id: "direction",
                    title: "Check your directional bias",
                    body: "You're taking more \(edge) trades (\(majority) of \(trades.count)). Confirm that matches your plan, bias without intent becomes drift.",
                    kind: .direction
                )
            )
        }

        return items
    }

    private static func money(_ value: Decimal) -> String {
        NumberDisplay.currency(value, minimumFractionDigits: 0, maximumFractionDigits: 2)
    }

    // MARK: - Legacy local expansion (non-V3 path only)

    private static func localSessionPerformance(_ trades: [Trade]) -> [DashboardSessionPerformanceRow] {
        let labels = TradingSessionCatalog.displayOrder
        return labels.compactMap { label in
            let scoped = trades.filter {
                TradingSessionLabel.canonicalLabel(fromStored: $0.sessionLabel) == label
            }
            guard !scoped.isEmpty else { return nil }
            let pnls = scoped.compactMap(\.realizedPnL?.amount)
            let wins = pnls.filter { $0 > 0 }.count
            let losses = pnls.filter { $0 < 0 }.count
            return DashboardSessionPerformanceRow(
                label: label,
                tradeCount: scoped.count,
                netPnL: NSDecimalNumber(decimal: pnls.reduce(0, +)).doubleValue,
                wins: wins,
                losses: losses,
                winRate: pnls.isEmpty ? nil : Double(wins) / Double(pnls.count) * 100
            )
        }
    }

    private static func localSymbolPerformance(_ trades: [Trade]) -> [DashboardSymbolPerformanceRow] {
        var map: [String: (pnl: Decimal, trades: Int, wins: Int, rrSum: Decimal, rrCount: Int)] = [:]
        for trade in trades {
            let key = trade.symbol.ticker
            var row = map[key] ?? (0, 0, 0, 0, 0)
            if let pnl = trade.realizedPnL?.amount {
                row.pnl += pnl
                row.trades += 1
                if pnl > 0 { row.wins += 1 }
            }
            if let rr = TradePointsAndRealizedRr.resolveRealizedRr(trade: trade) {
                row.rrSum += rr
                row.rrCount += 1
            }
            map[key] = row
        }
        return map.map { ticker, row in
            DashboardSymbolPerformanceRow(
                ticker: ticker,
                trades: row.trades,
                netPnL: NSDecimalNumber(decimal: row.pnl).doubleValue,
                winRate: row.trades > 0 ? Double(row.wins) / Double(row.trades) * 100 : nil,
                avgRR: row.rrCount > 0 ? NSDecimalNumber(decimal: row.rrSum / Decimal(row.rrCount)).doubleValue : nil
            )
        }
        .sorted { $0.netPnL > $1.netPnL }
        .prefix(12)
        .map { $0 }
    }

    private static func localDailyPerformance(_ trades: [Trade]) -> DashboardDailyPerformanceSnapshot? {
        var dayMap: [String: Decimal] = [:]
        for trade in trades {
            guard let key = DashboardTradingDayKey.key(for: trade),
                  let amount = trade.realizedPnL?.amount else { continue }
            dayMap[key, default: 0] += amount
        }
        guard !dayMap.isEmpty else { return nil }
        let values = dayMap.values.map { NSDecimalNumber(decimal: $0).doubleValue }
        let green = values.filter { $0 > 0 }.count
        return DashboardDailyPerformanceSnapshot(
            bestDayPnL: values.max() ?? 0,
            worstDayPnL: values.min() ?? 0,
            avgDayPnL: values.reduce(0, +) / Double(values.count),
            consistencyPct: Double(green) / Double(values.count) * 100,
            tradingDays: values.count
        )
    }

    private static func localStreaks(_ trades: [Trade]) -> DashboardStreakSnapshot? {
        let ordered = trades.sorted { ($0.exitAt ?? $0.entryAt) < ($1.exitAt ?? $1.entryAt) }
        guard !ordered.isEmpty else { return nil }
        var maxWin = 0
        var maxLoss = 0
        var tempType: String?
        var tempLen = 0
        for trade in ordered {
            guard let pnl = trade.realizedPnL?.amount else { continue }
            let type = pnl > 0 ? "win" : pnl < 0 ? "loss" : "even"
            if type == tempType { tempLen += 1 } else { tempLen = 1; tempType = type }
            if type == "win" { maxWin = max(maxWin, tempLen) }
            if type == "loss" { maxLoss = max(maxLoss, tempLen) }
        }
        return DashboardStreakSnapshot(
            currentStreak: tempLen,
            currentType: tempType,
            maxWinStreak: maxWin,
            maxLossStreak: maxLoss
        )
    }

    private static func localHourHighlights(_ trades: [Trade]) -> DashboardHourHighlights? {
        var map: [Int: Decimal] = [:]
        let calendar = TradingReportPeriods.eastern
        for trade in trades {
            let hour = calendar.component(.hour, from: trade.entryAt)
            guard let amount = trade.realizedPnL?.amount else { continue }
            map[hour, default: 0] += amount
        }
        guard map.count > 1 else { return nil }
        let best = map.max(by: { $0.value < $1.value })
        let worst = map.min(by: { $0.value < $1.value })
        return DashboardHourHighlights(
            bestHour: best?.key,
            worstHour: worst?.key,
            bestPnL: best.map { NSDecimalNumber(decimal: $0.value).doubleValue },
            worstPnL: worst.map { NSDecimalNumber(decimal: $0.value).doubleValue }
        )
    }

    private static func localLongShortComparison(_ trades: [Trade]) -> DashboardLongShortComparison? {
        func side(_ isLong: Bool) -> DashboardDirectionSideSnapshot? {
            let scoped = trades.filter { ($0.side == .long) == isLong }
            guard !scoped.isEmpty else { return nil }
            let pnls = scoped.compactMap(\.realizedPnL?.amount)
            let wins = pnls.filter { $0 > 0 }
            let losses = pnls.filter { $0 < 0 }
            let grossWins = wins.reduce(Decimal(0), +)
            let grossLoss = abs(losses.reduce(Decimal(0), +))
            var rrSum = Decimal(0)
            var rrCount = 0
            for trade in scoped {
                if let rr = TradePointsAndRealizedRr.resolveRealizedRr(trade: trade) {
                    rrSum += rr
                    rrCount += 1
                }
            }
            let net = pnls.reduce(Decimal(0), +)
            return DashboardDirectionSideSnapshot(
                trades: scoped.count,
                netPnL: NSDecimalNumber(decimal: net).doubleValue,
                wins: wins.count,
                losses: losses.count,
                winRate: pnls.isEmpty ? 0 : Double(wins.count) / Double(pnls.count) * 100,
                profitFactor: grossLoss > 0 ? NSDecimalNumber(decimal: grossWins / grossLoss).doubleValue : nil,
                expectancy: pnls.isEmpty ? nil : NSDecimalNumber(decimal: net / Decimal(pnls.count)).doubleValue,
                avgRR: rrCount > 0 ? NSDecimalNumber(decimal: rrSum / Decimal(rrCount)).doubleValue : nil,
                bestTrade: wins.max().map { NSDecimalNumber(decimal: $0).doubleValue },
                worstTrade: losses.min().map { NSDecimalNumber(decimal: $0).doubleValue }
            )
        }
        return DashboardLongShortComparison(long: side(true), short: side(false))
    }

    private static func localHoldExtremes(_ trades: [Trade]) -> [DashboardHoldExtremeSnapshot] {
        struct Row { var seconds: Double; var pnl: Double }
        var winners: [Row] = []
        var losers: [Row] = []
        for trade in trades {
            guard let exit = trade.exitAt else { continue }
            let seconds = exit.timeIntervalSince(trade.entryAt)
            guard seconds > 0 else { continue }
            guard let amount = trade.realizedPnL?.amount else { continue }
            let pnl = NSDecimalNumber(decimal: amount).doubleValue
            if pnl > 0 { winners.append(Row(seconds: seconds, pnl: pnl)) }
            if pnl < 0 { losers.append(Row(seconds: seconds, pnl: pnl)) }
        }
        var rows: [DashboardHoldExtremeSnapshot] = []
        if let fastest = winners.min(by: { $0.seconds < $1.seconds }) {
            rows.append(DashboardHoldExtremeSnapshot(label: "Fastest winner", durationSeconds: fastest.seconds, pnl: fastest.pnl))
        }
        if let longest = winners.max(by: { $0.seconds < $1.seconds }) {
            rows.append(DashboardHoldExtremeSnapshot(label: "Longest winner", durationSeconds: longest.seconds, pnl: longest.pnl))
        }
        if let fastest = losers.min(by: { $0.seconds < $1.seconds }) {
            rows.append(DashboardHoldExtremeSnapshot(label: "Fastest loser", durationSeconds: fastest.seconds, pnl: fastest.pnl))
        }
        if let longest = losers.max(by: { $0.seconds < $1.seconds }) {
            rows.append(DashboardHoldExtremeSnapshot(label: "Longest loser", durationSeconds: longest.seconds, pnl: longest.pnl))
        }
        return rows
    }

    private static func localStrategyHighlights(_ trades: [Trade]) -> DashboardStrategyHighlights? {
        var map: [String: (pnl: Decimal, trades: Int, wins: Int)] = [:]
        for trade in trades {
            let key = (trade.strategy ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            var row = map[key] ?? (0, 0, 0)
            guard let pnl = trade.realizedPnL?.amount else { continue }
            row.pnl += pnl
            row.trades += 1
            if pnl > 0 { row.wins += 1 }
            map[key] = row
        }
        let qualified = map.filter { $0.value.trades >= 5 }
        guard qualified.count >= 2 else { return nil }
        let best = qualified.max(by: { $0.value.pnl < $1.value.pnl })
        let worst = qualified.min(by: { $0.value.pnl < $1.value.pnl })
        func highlight(_ pair: (key: String, value: (pnl: Decimal, trades: Int, wins: Int))?) -> DashboardStrategyHighlight? {
            guard let pair else { return nil }
            return DashboardStrategyHighlight(
                strategy: pair.key,
                trades: pair.value.trades,
                netPnL: NSDecimalNumber(decimal: pair.value.pnl).doubleValue,
                winRate: Double(pair.value.wins) / Double(pair.value.trades) * 100
            )
        }
        let bestHighlight = (best?.value.pnl ?? 0) > 0 ? highlight(best.map { ($0.key, $0.value) }) : nil
        let worstHighlight = (worst?.value.pnl ?? 0) < 0 ? highlight(worst.map { ($0.key, $0.value) }) : nil
        guard bestHighlight != nil || worstHighlight != nil else { return nil }
        return DashboardStrategyHighlights(best: bestHighlight, worst: worstHighlight)
    }
}
