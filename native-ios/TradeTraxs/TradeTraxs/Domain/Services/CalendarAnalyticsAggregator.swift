import Foundation

/// Compose Calendar month presentation from analytical daily rows (Calendar V2).
nonisolated enum CalendarAnalyticsAggregator {
    static func filteredRows(
        _ rows: [AnalyticsDailyStatRowV1],
        accountFilter: DashboardAccountFilter,
        modeFilter: String?
    ) -> [AnalyticsDailyStatRowV1] {
        rows.filter { row in
            if let modeFilter, row.mode_effective != modeFilter { return false }
            if modeFilter == nil, row.mode_effective == "backtest" { return false }
            switch accountFilter {
            case .all:
                return true
            case .account(let id):
                return row.account_id == id.rawValue
            }
        }
    }

    static func daySummaries(from rows: [AnalyticsDailyStatRowV1]) -> [String: TradingDaySummary] {
        var buckets: [String: (
            pnl: Decimal,
            trades: Int,
            wins: Int,
            losses: Int,
            be: Int,
            grossProfit: Decimal,
            grossLoss: Decimal,
            accounts: Set<TradingAccountID>
        )] = [:]

        for row in rows {
            let pnl = analyticsDecimal(row.net_pnl)
            var bucket = buckets[row.calendar_day] ?? (0, 0, 0, 0, 0, 0, 0, [])
            bucket.pnl += pnl
            bucket.trades += row.trade_count
            bucket.wins += row.win_count
            bucket.losses += row.loss_count
            bucket.be += row.breakeven_count
            bucket.grossProfit += analyticsDecimal(row.gross_profit)
            bucket.grossLoss += analyticsDecimal(row.gross_loss)
            if let accountID = row.account_id {
                bucket.accounts.insert(TradingAccountID(accountID))
            }
            buckets[row.calendar_day] = bucket
        }

        var result: [String: TradingDaySummary] = [:]
        for (key, bucket) in buckets {
            result[key] = TradingDaySummary(
                dayKey: key,
                netPnL: bucket.pnl,
                tradeCount: bucket.trades,
                winCount: bucket.wins,
                lossCount: bucket.losses,
                breakevenCount: bucket.be,
                grossProfit: bucket.grossProfit,
                grossLoss: bucket.grossLoss,
                tradeIDs: [],
                accountIDs: Array(bucket.accounts)
            )
        }
        return result
    }

    static func buildMonth(
        year: Int,
        month: Int,
        rows: [AnalyticsDailyStatRowV1],
        accountFilter: DashboardAccountFilter,
        modeFilter: String? = nil,
        todayKey: String? = AnalyticsCalendarDay.todayKey()
    ) -> TradingCalendarMonth {
        let scoped = filteredRows(rows, accountFilter: accountFilter, modeFilter: modeFilter)
        let monthDays = daySummaries(from: scoped).filter {
            $0.key.hasPrefix(String(format: "%04d-%02d-", year, month))
        }

        let cells = TradingCalendarAggregator.makeGridCells(
            year: year,
            month: month,
            days: monthDays,
            todayKey: todayKey
        )
        let weeks = TradingCalendarAggregator.weekSummaries(from: cells)
        let summary = monthSummary(year: year, month: month, days: monthDays, scopedRows: scoped)

        return TradingCalendarMonth(
            year: year,
            month: month,
            title: AnalyticsCalendarDay.monthTitle(year: year, month: month),
            cells: cells,
            weekSummaries: weeks,
            monthSummary: summary,
            days: monthDays
        )
    }

    static func monthSummary(
        year: Int,
        month: Int,
        days: [String: TradingDaySummary],
        scopedRows: [AnalyticsDailyStatRowV1]
    ) -> TradingMonthSummary {
        let values = Array(days.values)
        let net = values.reduce(Decimal(0)) { $0 + $1.netPnL }
        let tradeCount = values.reduce(0) { $0 + $1.tradeCount }
        let wins = scopedRows.reduce(0) { $0 + $1.win_count }
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
            tradeWinRate: tradeCount > 0 ? Decimal(wins) / Decimal(tradeCount) : nil
        )
    }

    static func buildYearOverview(
        year: Int,
        rows: [AnalyticsDailyStatRowV1],
        accountFilter: DashboardAccountFilter,
        modeFilter: String? = nil,
        now: Date = Date()
    ) -> TradingYearOverview {
        let current = CalendarMonthID.current(now: now)
        var cards: [TradingYearMonthCard] = []
        var totalNet: Decimal = 0
        var totalTradingDays = 0
        var winWeighted: Decimal = 0
        var tradeCountTotal: Decimal = 0
        var bestAbbrev: String?
        var bestPnL: Decimal?

        for month in 1...12 {
            let built = buildMonth(
                year: year,
                month: month,
                rows: rows,
                accountFilter: accountFilter,
                modeFilter: modeFilter
            )
            let isFuture = year > current.year || (year == current.year && month > current.month)
            let summary = built.monthSummary
            let abbrev = AnalyticsCalendarDay.monthAbbreviation(year: year, month: month)

            if !isFuture {
                totalNet += summary.netPnL
                totalTradingDays += summary.tradingDayCount
                if summary.tradeCount > 0, let rate = summary.tradeWinRate {
                    winWeighted += rate * Decimal(summary.tradeCount)
                    tradeCountTotal += Decimal(summary.tradeCount)
                }
                if summary.tradingDayCount > 0 {
                    if bestPnL == nil || summary.netPnL > (bestPnL ?? 0) {
                        bestPnL = summary.netPnL
                        bestAbbrev = abbrev
                    }
                }
            }

            cards.append(
                TradingYearMonthCard(
                    month: month,
                    abbreviation: abbrev,
                    summary: isFuture
                        ? TradingMonthSummary(
                            year: year,
                            month: month,
                            netPnL: 0,
                            tradeCount: 0,
                            tradingDayCount: 0,
                            winningDayCount: 0,
                            losingDayCount: 0,
                            breakevenDayCount: 0,
                            bestDayKey: nil,
                            bestDayPnL: nil,
                            worstDayKey: nil,
                            worstDayPnL: nil,
                            averageDailyPnL: nil,
                            tradeWinRate: nil
                        )
                        : summary,
                    isFutureMonth: isFuture
                )
            )
        }

        let winRate: Decimal? = tradeCountTotal > 0 ? winWeighted / tradeCountTotal : nil

        return TradingYearOverview(
            year: year,
            months: cards,
            netPnL: totalNet,
            tradingDayCount: totalTradingDays,
            tradeWinRate: winRate,
            bestMonthAbbreviation: bestAbbrev,
            bestMonthPnL: bestPnL
        )
    }
}

nonisolated private func analyticsDecimal(_ wire: PostgresFlexibleDouble) -> Decimal {
    guard let value = wire.value else { return 0 }
    return Decimal(value)
}
