import Foundation

/// Presentation aggregations for the native Dashboard.
///
/// Formulas mirror web `useDashboardAnalytics` / `dashboardMaxDrawdown` /
/// `dashboardHoldTimeStats` / session buckets — no repository changes.
nonisolated enum DashboardChartMetrics {
    struct Input: Sendable, Equatable {
        var trade: Trade
        var accountType: String?
    }

    struct Summary: Sendable, Equatable {
        var netPnL: Decimal
        var winRate: Decimal?
        var profitFactor: Decimal?
        var payouts: Decimal?
        var expectancy: Decimal?
        var averageRR: Decimal?
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
        var winLoss: [DashboardWinLossPoint]
        var holdTime: [DashboardHoldTimeRow]
        var insights: [DashboardInsightItem]
    }

    static func compute(
        from inputs: [Input],
        accountFilter: DashboardAccountFilter,
        dateRange: DashboardDateRange,
        payoutTotal: Decimal?,
        now: Date = Date()
    ) -> Summary {
        let filtered = filter(inputs, accountFilter: accountFilter, dateRange: dateRange, now: now)
        let trades = filtered.map(\.trade)

        let pnlValues = trades.map { $0.realizedPnL?.amount ?? 0 }
        let wins = pnlValues.filter { $0 > 0 }
        let losses = pnlValues.filter { $0 < 0 }
        let tradeCount = trades.count
        let winCount = wins.count
        let lossCount = losses.count
        let netPnL = pnlValues.reduce(0, +)

        let winRate: Decimal? = tradeCount > 0 ? Decimal(winCount) / Decimal(tradeCount) : nil
        let grossWins = wins.reduce(Decimal(0), +)
        let grossLosses = losses.reduce(Decimal(0), +)
        let profitFactor: Decimal? = grossLosses < 0 ? grossWins / abs(grossLosses) : nil

        let avgWin: Decimal? = winCount > 0 ? grossWins / Decimal(winCount) : nil
        let avgLossAbs: Decimal? = lossCount > 0 ? abs(grossLosses) / Decimal(lossCount) : nil
        let lossRate: Decimal = tradeCount > 0 ? Decimal(lossCount) / Decimal(tradeCount) : 0
        let winRateFrac: Decimal = winRate ?? 0
        let expectancy: Decimal? = {
            guard tradeCount > 0 else { return nil }
            return winRateFrac * (avgWin ?? 0) - lossRate * (avgLossAbs ?? 0)
        }()

        var rrSum = Decimal(0)
        var rrCount = 0
        for trade in trades {
            guard let rr = trade.riskReward else { continue }
            rrSum += rr
            rrCount += 1
        }
        let averageRR: Decimal? = rrCount > 0 ? rrSum / Decimal(rrCount) : nil

        let statsInputs = filtered.map {
            ProfileStatisticsMetrics.TradeInput(
                pnl: $0.trade.realizedPnL?.amount,
                createdAt: $0.trade.entryAt,
                isLong: $0.trade.side == .long,
                session: $0.trade.sessionLabel,
                mode: $0.trade.mode.rawValue,
                accountType: $0.accountType
            )
        }
        let profileStats = ProfileStatisticsMetrics.compute(from: statsInputs, selectedMode: .all)

        return Summary(
            netPnL: netPnL,
            winRate: winRate,
            profitFactor: profitFactor,
            payouts: payoutTotal,
            expectancy: expectancy,
            averageRR: averageRR,
            tradeCount: tradeCount,
            winCount: winCount,
            lossCount: lossCount,
            avgWin: avgWin,
            avgLoss: avgLossAbs.map { -$0 },
            bestTrade: pnlValues.max(),
            biggestLoss: losses.min(),
            maxDrawdown: maxDrawdown(trades),
            currentEquity: profileStats.currentEquity,
            equityData: profileStats.equityData,
            sessions: profileStats.sessionBreakdown,
            weekdays: weekdayBars(trades),
            hours: hourBars(trades),
            longShort: longShortBars(trades),
            winLoss: [
                DashboardWinLossPoint(label: "Wins", count: winCount),
                DashboardWinLossPoint(label: "Losses", count: lossCount),
            ],
            holdTime: holdTimeRows(trades),
            insights: insightItems(trades: trades, sessions: profileStats.sessionBreakdown)
        )
    }

    // MARK: - Filter (web time + account)

    private static func filter(
        _ inputs: [Input],
        accountFilter: DashboardAccountFilter,
        dateRange: DashboardDateRange,
        now: Date
    ) -> [Input] {
        inputs.filter { input in
            let trade = input.trade
            // Exclude backtest — same as ProfileStatisticsMetrics / web dashboard.
            let mode = trade.mode.rawValue.lowercased()
            let accountType = (input.accountType ?? "").lowercased()
            if mode == "backtest" || accountType == "backtest" { return false }

            switch accountFilter {
            case .all:
                break
            case .account(let id):
                guard trade.accountID == id else { return false }
            }

            let stamp = trade.exitAt ?? trade.entryAt
            return dateRange.contains(stamp, now: now)
        }
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
            running += trade.realizedPnL?.amount ?? 0
            if running > peak { peak = running }
            let drawdown = peak - running
            if drawdown > maxDD { maxDD = drawdown }
        }
        return maxDD
    }

    // MARK: - Weekdays / Hours

    private static func weekdayBars(_ trades: [Trade]) -> [DashboardBarPoint] {
        let labels = ["Mon", "Tue", "Wed", "Thu", "Fri"]
        var map: [Int: Decimal] = [:] // 2...6 Mon-Fri in Gregorian when firstWeekday=1
        let calendar = Calendar.current
        for trade in trades {
            let date = trade.entryAt
            let weekday = calendar.component(.weekday, from: date) // 1=Sun
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
            map[index, default: 0] += trade.realizedPnL?.amount ?? 0
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
        let calendar = Calendar.current
        for trade in trades {
            let hour = calendar.component(.hour, from: trade.entryAt)
            map[hour, default: 0] += trade.realizedPnL?.amount ?? 0
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
        let longPnL = trades.filter { $0.side == .long }
            .reduce(Decimal(0)) { $0 + ($1.realizedPnL?.amount ?? 0) }
        let shortPnL = trades.filter { $0.side == .short }
            .reduce(Decimal(0)) { $0 + ($1.realizedPnL?.amount ?? 0) }
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

    private static func holdTimeRows(_ trades: [Trade]) -> [DashboardHoldTimeRow] {
        var all: [TimeInterval] = []
        var win: [TimeInterval] = []
        var loss: [TimeInterval] = []
        for trade in trades {
            guard let exit = trade.exitAt else { continue }
            let seconds = exit.timeIntervalSince(trade.entryAt)
            guard seconds > 0 else { continue }
            all.append(seconds)
            let pnl = trade.realizedPnL?.amount ?? 0
            if pnl > 0 { win.append(seconds) }
            else if pnl < 0 { loss.append(seconds) }
        }
        guard !all.isEmpty else { return [] }
        return [
            DashboardHoldTimeRow(label: "Avg Hold", value: formatDuration(average(all))),
            DashboardHoldTimeRow(label: "Avg Winner", value: formatDuration(average(win))),
            DashboardHoldTimeRow(label: "Avg Loser", value: formatDuration(average(loss))),
        ]
    }

    private static func average(_ values: [TimeInterval]) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func formatDuration(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "—" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(total)s"
    }

    // MARK: - Insights (web generateInsights subset)

    private static func insightItems(
        trades: [Trade],
        sessions: [ProfileStatisticsMetrics.SessionRow]
    ) -> [DashboardInsightItem] {
        var items: [DashboardInsightItem] = []
        if let bestSession = sessions.max(by: { $0.pct < $1.pct }) {
            items.append(
                DashboardInsightItem(
                    id: "session",
                    body: "Most of your tagged volume is in the \(bestSession.label) session (\(Int(bestSession.pct.rounded()))%)."
                )
            )
        }

        var symbolPnL: [String: (pnl: Decimal, count: Int)] = [:]
        for trade in trades {
            let key = trade.symbol.ticker
            let current = symbolPnL[key] ?? (0, 0)
            symbolPnL[key] = (current.pnl + (trade.realizedPnL?.amount ?? 0), current.count + 1)
        }
        if let best = symbolPnL
            .filter({ $0.value.count >= 3 })
            .max(by: { ($0.value.pnl / Decimal($0.value.count)) < ($1.value.pnl / Decimal($1.value.count)) })
        {
            let avg = best.value.pnl / Decimal(best.value.count)
            items.append(
                DashboardInsightItem(
                    id: "symbol",
                    body: "\(best.key) is your strongest market (\(money(avg)) avg over \(best.value.count) trades)."
                )
            )
        }

        let longCount = trades.filter { $0.side == .long }.count
        let shortCount = trades.count - longCount
        if trades.count >= 5 {
            let edge = longCount >= shortCount ? "Long" : "Short"
            items.append(
                DashboardInsightItem(
                    id: "direction",
                    body: "You take more \(edge.lowercased()) trades (\(max(longCount, shortCount)) of \(trades.count))."
                )
            )
        }

        return items
    }

    private static func money(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value).doubleValue
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: number)) ?? "$0"
    }
}
