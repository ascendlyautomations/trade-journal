import Foundation

/// Calendar aggregation for backtest-only trade pools (main calendar excludes backtest).
nonisolated enum BacktestLabCalendarSupport {
    static func daySummaries(from trades: [Trade]) -> [String: TradingDaySummary] {
        var buckets: [String: (pnl: Decimal, wins: Int, losses: Int, be: Int, grossProfit: Decimal, grossLoss: Decimal, ids: [TradeID], accounts: Set<TradingAccountID>)] = [:]

        for trade in trades where trade.mode == .backtest {
            guard let dayKey = TradingCalendarDay.key(for: trade) else { continue }
            let pnl = trade.realizedPnL?.amount ?? 0
            var bucket = buckets[dayKey] ?? (0, 0, 0, 0, 0, 0, [], [])
            bucket.pnl += pnl
            if pnl > 0 {
                bucket.wins += 1
                bucket.grossProfit += pnl
            } else if pnl < 0 {
                bucket.losses += 1
                bucket.grossLoss += pnl
            } else {
                bucket.be += 1
            }
            bucket.ids.append(trade.id)
            if let accountID = trade.accountID {
                bucket.accounts.insert(accountID)
            }
            buckets[dayKey] = bucket
        }

        var result: [String: TradingDaySummary] = [:]
        for (key, bucket) in buckets {
            result[key] = TradingDaySummary(
                dayKey: key,
                netPnL: bucket.pnl,
                tradeCount: bucket.ids.count,
                winCount: bucket.wins,
                lossCount: bucket.losses,
                breakevenCount: bucket.be,
                grossProfit: bucket.grossProfit,
                grossLoss: bucket.grossLoss,
                tradeIDs: bucket.ids,
                accountIDs: Array(bucket.accounts)
            )
        }
        return result
    }

    static func buildMonth(
        year: Int,
        month: Int,
        trades: [Trade],
        todayKey: String? = TradingCalendarDay.todayKey()
    ) -> TradingCalendarMonth {
        let allDays = daySummaries(from: trades)
        let prefix = String(format: "%04d-%02d-", year, month)
        let monthDays = allDays.filter { $0.key.hasPrefix(prefix) }
        let cells = TradingCalendarAggregator.makeGridCells(
            year: year,
            month: month,
            days: monthDays,
            todayKey: todayKey
        )
        let weeks = TradingCalendarAggregator.weekSummaries(from: cells)
        let summary = monthSummary(year: year, month: month, days: monthDays)

        return TradingCalendarMonth(
            year: year,
            month: month,
            title: TradingCalendarDay.monthTitle(year: year, month: month),
            cells: cells,
            weekSummaries: weeks,
            monthSummary: summary,
            days: monthDays
        )
    }

    private static func monthSummary(
        year: Int,
        month: Int,
        days: [String: TradingDaySummary]
    ) -> TradingMonthSummary {
        let values = Array(days.values)
        let net = values.reduce(Decimal(0)) { $0 + $1.netPnL }
        let tradeCount = values.reduce(0) { $0 + $1.tradeCount }
        let winningDays = values.filter { $0.outcome == .profit }.count
        let losingDays = values.filter { $0.outcome == .loss }.count
        let beDays = values.filter { $0.outcome == .breakeven }.count
        let best = values.max(by: { $0.netPnL < $1.netPnL })
        let worst = values.min(by: { $0.netPnL < $1.netPnL })
        let avg: Decimal? = values.isEmpty ? nil : net / Decimal(values.count)

        return TradingMonthSummary(
            year: year,
            month: month,
            netPnL: net,
            tradeCount: tradeCount,
            tradingDayCount: values.count,
            winningDayCount: winningDays,
            losingDayCount: losingDays,
            breakevenDayCount: beDays,
            bestDayKey: best?.dayKey,
            bestDayPnL: best?.netPnL,
            worstDayKey: worst?.dayKey,
            worstDayPnL: worst?.netPnL,
            averageDailyPnL: avg,
            tradeWinRate: nil
        )
    }
}
