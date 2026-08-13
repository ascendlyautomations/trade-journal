import Foundation

/// Pure aggregation — web Calendar `dailyData` / week totals / monthly stats subset.
nonisolated enum TradingCalendarAggregator {
    /// Groups trades into futures trading days, filtering by account.
    static func daySummaries(
        from trades: [Trade],
        accountFilter: DashboardAccountFilter
    ) -> [String: TradingDaySummary] {
        var buckets: [String: (pnl: Decimal, wins: Int, losses: Int, be: Int, grossProfit: Decimal, grossLoss: Decimal, ids: [TradeID], accounts: Set<TradingAccountID>)] = [:]

        for trade in trades {
            switch accountFilter {
            case .all:
                break
            case .account(let id):
                guard trade.accountID == id else { continue }
            }
            // Exclude backtest from calendar performance (Dashboard parity).
            if trade.mode == .backtest { continue }

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
        accountFilter: DashboardAccountFilter,
        todayKey: String? = TradingCalendarDay.todayKey()
    ) -> TradingCalendarMonth {
        let allDays = daySummaries(from: trades, accountFilter: accountFilter)
        let prefix = String(format: "%04d-%02d-", year, month)
        let monthDays = allDays.filter { $0.key.hasPrefix(prefix) }

        let cells = makeGridCells(
            year: year,
            month: month,
            days: monthDays,
            todayKey: todayKey
        )
        let weeks = weekSummaries(from: cells)
        let summary = monthSummary(year: year, month: month, days: monthDays, trades: trades, accountFilter: accountFilter)

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

    /// Sunday-start grid (web Calendar). Leading/trailing days included but marked out-of-month.
    static func makeGridCells(
        year: Int,
        month: Int,
        days: [String: TradingDaySummary],
        todayKey: String?
    ) -> [CalendarGridCell] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1 // Sunday
        calendar.timeZone = TradingCalendarDay.timeZone

        guard let monthStart = calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: TradingCalendarDay.timeZone,
            year: year,
            month: month,
            day: 1
        )) else { return [] }

        let weekday = calendar.component(.weekday, from: monthStart) // 1=Sun
        let leading = weekday - calendar.firstWeekday
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30

        var cells: [CalendarGridCell] = []
        // Leading
        if leading > 0, let prevMonth = calendar.date(byAdding: .month, value: -1, to: monthStart) {
            let prevDays = calendar.range(of: .day, in: .month, for: prevMonth)?.count ?? 30
            let prevComps = calendar.dateComponents([.year, .month], from: prevMonth)
            for offset in 0..<leading {
                let day = prevDays - leading + offset + 1
                let key = String(
                    format: "%04d-%02d-%02d",
                    prevComps.year ?? year,
                    prevComps.month ?? month,
                    day
                )
                cells.append(CalendarGridCell(
                    id: "pad-\(key)",
                    dayKey: key,
                    dayNumber: day,
                    isCurrentMonth: false,
                    isToday: key == todayKey,
                    summary: days[key]
                ))
            }
        }

        for day in 1...daysInMonth {
            let key = String(format: "%04d-%02d-%02d", year, month, day)
            cells.append(CalendarGridCell(
                id: key,
                dayKey: key,
                dayNumber: day,
                isCurrentMonth: true,
                isToday: key == todayKey,
                summary: days[key]
            ))
        }

        // Trailing to complete weeks
        var trailingDay = 1
        let nextComps: DateComponents = {
            guard let next = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
                return DateComponents(year: year, month: month == 12 ? 1 : month + 1)
            }
            return calendar.dateComponents([.year, .month], from: next)
        }()
        while cells.count % 7 != 0 {
            let key = String(
                format: "%04d-%02d-%02d",
                nextComps.year ?? year,
                nextComps.month ?? month,
                trailingDay
            )
            cells.append(CalendarGridCell(
                id: "trail-\(key)",
                dayKey: key,
                dayNumber: trailingDay,
                isCurrentMonth: false,
                isToday: key == todayKey,
                summary: days[key]
            ))
            trailingDay += 1
        }
        return cells
    }

    static func weekSummaries(from cells: [CalendarGridCell]) -> [TradingWeekSummary] {
        stride(from: 0, to: cells.count, by: 7).map { start in
            let slice = cells[start..<min(start + 7, cells.count)]
            // Web week total includes only current-month days in the row for display clarity
            // but sums all non-null day P&Ls in the row. Match web: sum day summaries present.
            var pnl: Decimal = 0
            var trades = 0
            var tradingDays = 0
            for cell in slice where cell.isCurrentMonth {
                if let summary = cell.summary {
                    pnl += summary.netPnL
                    trades += summary.tradeCount
                    tradingDays += 1
                }
            }
            return TradingWeekSummary(
                id: "week-\(start / 7)",
                netPnL: pnl,
                tradeCount: trades,
                tradingDayCount: tradingDays
            )
        }
    }

    static func monthSummary(
        year: Int,
        month: Int,
        days: [String: TradingDaySummary],
        trades: [Trade],
        accountFilter: DashboardAccountFilter
    ) -> TradingMonthSummary {
        let values = Array(days.values)
        let net = values.reduce(Decimal(0)) { $0 + $1.netPnL }
        let tradeCount = values.reduce(0) { $0 + $1.tradeCount }
        var wins = 0
        var losses = 0
        for trade in trades {
            switch accountFilter {
            case .all: break
            case .account(let id):
                guard trade.accountID == id else { continue }
            }
            if trade.mode == .backtest { continue }
            guard let key = TradingCalendarDay.key(for: trade),
                  key.hasPrefix(String(format: "%04d-%02d-", year, month))
            else { continue }
            let pnl = trade.realizedPnL?.amount ?? 0
            if pnl > 0 { wins += 1 }
            else if pnl < 0 { losses += 1 }
        }

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

    static func trades(
        for dayKey: String,
        from trades: [Trade],
        accountFilter: DashboardAccountFilter
    ) -> [Trade] {
        trades.filter { trade in
            switch accountFilter {
            case .all: break
            case .account(let id):
                guard trade.accountID == id else { return false }
            }
            if trade.mode == .backtest { return false }
            return TradingCalendarDay.key(for: trade) == dayKey
        }
        .sorted { $0.createdAt > $1.createdAt }
    }
}
