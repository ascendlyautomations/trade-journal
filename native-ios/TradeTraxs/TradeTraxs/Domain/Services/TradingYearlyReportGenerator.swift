import Foundation

/// Yearly + month drill-down Performance Reports — reuses ``DashboardChartMetrics``.
nonisolated enum TradingYearlyReportGenerator {
    static func availableYears(
        from trades: [Trade],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Int] {
        TradingReportPeriods.availableYears(from: trades, now: now, calendar: calendar)
    }

    static func generate(
        year: Int,
        trades: [Trade],
        filters: TradingReportFilters,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TradingYearlyReport {
        let bounds = TradingReportPeriods.yearBounds(year: year, now: now, calendar: calendar)
        let interval = DateInterval(start: bounds.start, end: bounds.end)
        let inputs = trades.map {
            DashboardChartMetrics.Input(trade: $0, accountType: nil)
        }
        let scopedTrades = DashboardChartMetrics.filteredTrades(
            from: inputs,
            accountFilter: filters.accountFilter,
            accountMode: filters.accountMode,
            interval: interval,
            now: now
        )
        let summary = DashboardChartMetrics.compute(
            from: inputs,
            accountFilter: filters.accountFilter,
            accountMode: filters.accountMode,
            interval: interval,
            payoutTotal: nil,
            now: now
        )

        let daily = computeDailyPnl(scopedTrades, calendar: calendar)
        let bestDay = pickExtremeDay(daily, mode: .best, calendar: calendar)
        let worstDay = pickExtremeDay(daily, mode: .worst, calendar: calendar)
        let winningDays = daily.values.filter { $0 > 0 }.count
        let losingDays = daily.values.filter { $0 < 0 }.count

        let metrics = TradingYearlyReportMetrics(
            netPnl: summary.netPnL,
            tradeCount: summary.tradeCount,
            winRate: summary.winRate,
            profitFactor: summary.profitFactor,
            averageWinner: summary.avgWin,
            averageLoser: summary.avgLoss,
            averageRR: summary.averageRR,
            expectancy: summary.expectancy,
            bestTrade: summary.bestTrade,
            worstTrade: summary.biggestLoss,
            bestDayLabel: bestDay.label,
            bestDayPnl: bestDay.pnl,
            worstDayLabel: worstDay.label,
            worstDayPnl: worstDay.pnl,
            maxDrawdown: summary.maxDrawdown,
            winningDays: winningDays,
            losingDays: losingDays
        )

        let monthRows = buildMonthRows(
            year: year,
            trades: trades,
            filters: filters,
            now: now,
            calendar: calendar
        )
        let availableMonths = monthRows.compactMap { row -> TradingYearlyMonthMetrics? in
            if case .available(let metrics) = row.availability { return metrics }
            return nil
        }
        let strongestMonth = availableMonths
            .filter { $0.tradeCount > 0 }
            .max(by: { $0.netPnl < $1.netPnl })
        let weakestMonth = availableMonths
            .filter { $0.tradeCount > 0 }
            .min(by: { $0.netPnl < $1.netPnl })

        let monthlyBars = monthRows.compactMap { row -> DashboardBarPoint? in
            guard case .available(let metrics) = row.availability else { return nil }
            return DashboardBarPoint(
                label: shortMonthLabel(row.month, calendar: calendar),
                value: NSDecimalNumber(decimal: metrics.netPnl).doubleValue
            )
        }

        return TradingYearlyReport(
            year: year,
            filters: filters,
            title: "\(year) Performance Report",
            dateRangeLabel: TradingReportPeriods.yearDateRangeLabel(
                year: year,
                now: now,
                calendar: calendar
            ),
            periodStartIso: isoString(bounds.start),
            periodEndIso: isoString(bounds.end),
            generatedAt: now.timeIntervalSince1970 * 1000,
            executiveSummary: buildExecutiveSummary(metrics: metrics, year: year),
            metrics: metrics,
            monthRows: monthRows,
            chartSummary: summary,
            monthlyPnLBars: monthlyBars,
            strongestMonth: strongestMonth,
            weakestMonth: weakestMonth
        )
    }

    /// Month drill-down — same filters and trade scope as yearly reports.
    static func generateMonthReport(
        ref: TradingReportMonthRef,
        trades: [Trade],
        filters: TradingReportFilters,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TradingReport {
        let bounds = TradingReportPeriods.monthBounds(
            year: ref.year,
            month: ref.month,
            now: now,
            calendar: calendar
        )
        let interval = DateInterval(start: bounds.start, end: bounds.end)
        let inputs = trades.map {
            DashboardChartMetrics.Input(trade: $0, accountType: nil)
        }
        let scopedTrades = DashboardChartMetrics.filteredTrades(
            from: inputs,
            accountFilter: filters.accountFilter,
            accountMode: filters.accountMode,
            interval: interval,
            now: now
        )
        let metrics = TradingReportGeneratorMetricsBridge.buildMetrics(from: scopedTrades, calendar: calendar)

        return TradingReport(
            periodKey: .monthlyThis,
            kind: .monthly,
            title: "\(monthLabel(ref.month, calendar: calendar)) \(ref.year) Report",
            dateRangeLabel: TradingCalendarDay.monthTitle(year: ref.year, month: ref.month),
            periodStartIso: isoString(bounds.start),
            periodEndIso: isoString(bounds.end),
            generatedAt: now.timeIntervalSince1970 * 1000,
            executiveSummary: buildMonthExecutiveSummary(metrics: metrics, ref: ref, calendar: calendar),
            metrics: metrics,
            strengths: [],
            opportunities: [],
            recommendations: [],
            bestTradeId: findBestTradeID(scopedTrades),
            keyTakeaway: buildMonthKeyTakeaway(metrics: metrics),
            summarySource: "deterministic"
        )
    }

    // MARK: - Month rows

    private static func buildMonthRows(
        year: Int,
        trades: [Trade],
        filters: TradingReportFilters,
        now: Date,
        calendar: Calendar
    ) -> [TradingYearlyMonthRow] {
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)
        let inputs = trades.map { DashboardChartMetrics.Input(trade: $0, accountType: nil) }

        return (1...12).map { month in
            let label = monthLabel(month, calendar: calendar)
            if year > currentYear || (year == currentYear && month > currentMonth) {
                return TradingYearlyMonthRow(
                    month: month,
                    monthLabel: label,
                    availability: .upcoming
                )
            }

            let bounds = TradingReportPeriods.monthBounds(
                year: year,
                month: month,
                now: now,
                calendar: calendar
            )
            let interval = DateInterval(start: bounds.start, end: bounds.end)
            let summary = DashboardChartMetrics.compute(
                from: inputs,
                accountFilter: filters.accountFilter,
                accountMode: filters.accountMode,
                interval: interval,
                payoutTotal: nil,
                now: now
            )
            let ref = TradingReportMonthRef(year: year, month: month)
            let metrics = TradingYearlyMonthMetrics(
                year: year,
                month: month,
                monthLabel: label,
                netPnl: summary.netPnL,
                tradeCount: summary.tradeCount,
                winRate: summary.winRate,
                monthRef: ref
            )
            return TradingYearlyMonthRow(
                month: month,
                monthLabel: label,
                availability: .available(metrics)
            )
        }
    }

    // MARK: - Narrative

    private static func buildExecutiveSummary(
        metrics: TradingYearlyReportMetrics,
        year: Int
    ) -> String {
        if metrics.tradeCount == 0 {
            return "No trades matched your filters during \(year). Adjust filters or log trades to unlock yearly insights."
        }

        let tone: String = {
            if metrics.netPnl > 0 { return "positive" }
            if metrics.netPnl < 0 { return "challenging" }
            return "mixed"
        }()

        let winRateText: String = {
            guard let winRate = metrics.winRate else { return "no closed trades" }
            return String(format: "%.1f%% win rate", NSDecimalNumber(decimal: winRate * 100).doubleValue)
        }()

        return "\(year) was a \(tone) year with \(metrics.tradeCount) trades and \(formatMoney(metrics.netPnl)) net P&L. You finished with \(winRateText) across \(metrics.winningDays) winning days and \(metrics.losingDays) losing days."
    }

    private static func buildMonthExecutiveSummary(
        metrics: TradingReportMetrics,
        ref: TradingReportMonthRef,
        calendar: Calendar
    ) -> String {
        let label = monthLabel(ref.month, calendar: calendar)
        if metrics.tradesTaken == 0 {
            return "No trades matched your filters during \(label) \(ref.year)."
        }
        return "\(label) \(ref.year): \(metrics.tradesTaken) trades and \(formatPnl(metrics.netPnl)) net P&L with \(String(format: "%.1f%%", metrics.winRate)) win rate."
    }

    private static func buildMonthKeyTakeaway(metrics: TradingReportMetrics) -> String {
        if metrics.tradesTaken == 0 {
            return "This month had no matching trades for your active filters."
        }
        if metrics.netPnl > 0 {
            return "Net positive month — review what worked and carry those habits forward."
        }
        if metrics.netPnl < 0 {
            return "Review session timing and risk per trade to tighten execution next month."
        }
        return "Stay process-focused — small adjustments compound across the year."
    }

    // MARK: - Helpers

    private enum ExtremeMode { case best, worst }

    private static func computeDailyPnl(_ trades: [Trade], calendar: Calendar) -> [String: Decimal] {
        var map: [String: Decimal] = [:]
        for trade in trades {
            guard let key = TradingCalendarDay.key(for: trade) else { continue }
            map[key, default: 0] += trade.realizedPnL?.amount ?? 0
        }
        return map
    }

    private static func pickExtremeDay(
        _ daily: [String: Decimal],
        mode: ExtremeMode,
        calendar: Calendar
    ) -> (label: String?, pnl: Decimal?) {
        guard !daily.isEmpty else { return (nil, nil) }
        let picked: (key: String, pnl: Decimal)? = {
            switch mode {
            case .best: return daily.max(by: { $0.value < $1.value }).map { ($0.key, $0.value) }
            case .worst: return daily.min(by: { $0.value < $1.value }).map { ($0.key, $0.value) }
            }
        }()
        guard let picked else { return (nil, nil) }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
        if let date = dayKeyDate(picked.key) {
            return (formatter.string(from: date), picked.pnl)
        }
        return (picked.key, picked.pnl)
    }

    private static func findBestTradeID(_ trades: [Trade]) -> String? {
        trades.max(by: {
            NSDecimalNumber(decimal: $0.realizedPnL?.amount ?? 0).doubleValue
                < NSDecimalNumber(decimal: $1.realizedPnL?.amount ?? 0).doubleValue
        })?.id.rawValue
    }

    private static func monthLabel(_ month: Int, calendar: Calendar) -> String {
        guard let date = calendar.date(from: DateComponents(year: 2024, month: month, day: 1)) else {
            return "Month \(month)"
        }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMM")
        return formatter.string(from: date)
    }

    private static func shortMonthLabel(_ month: Int, calendar: Calendar) -> String {
        guard let date = calendar.date(from: DateComponents(year: 2024, month: month, day: 1)) else {
            return "\(month)"
        }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter.string(from: date)
    }

    private static func dayKeyDate(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(
            year: parts[0],
            month: parts[1],
            day: parts[2],
            hour: 12
        ))
    }

    private static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func formatMoney(_ value: Decimal) -> String {
        formatPnl(NSDecimalNumber(decimal: value).doubleValue)
    }

    private static func formatPnl(_ value: Double) -> String {
        let absValue = abs(value)
        let formatted = absValue.formatted(
            .number.precision(.fractionLength(2)).grouping(.automatic)
        )
        return value < 0 ? "-$\(formatted)" : "$\(formatted)"
    }
}

/// Bridges scoped trades into ``TradingReportMetrics`` for month drill-down reuse.
nonisolated enum TradingReportGeneratorMetricsBridge {
    static func buildMetrics(from trades: [Trade], calendar: Calendar = .current) -> TradingReportMetrics {
        let totalTrades = trades.count
        let wins = trades.filter { pnl($0) > 0 }.count
        let winRate = totalTrades > 0 ? (Double(wins) / Double(totalTrades)) * 100 : 0
        let totalPnL = trades.reduce(0.0) { $0 + pnl($1) }
        let daily = computeDailyPnl(trades)
        let bestDay = pickExtremeDay(daily, mode: .best, calendar: calendar)
        let worstDay = pickExtremeDay(daily, mode: .worst, calendar: calendar)

        return TradingReportMetrics(
            netPnl: totalPnL,
            winRate: winRate,
            averageRr: averageRr(trades),
            profitFactor: computeProfitFactor(trades),
            tradesTaken: totalTrades,
            bestDayLabel: bestDay.label,
            bestDayPnl: bestDay.pnl.map { NSDecimalNumber(decimal: $0).doubleValue },
            worstDayLabel: worstDay.label,
            worstDayPnl: worstDay.pnl.map { NSDecimalNumber(decimal: $0).doubleValue },
            bestSessionLabel: nil,
            bestSessionPnl: nil,
            worstSessionLabel: nil,
            worstSessionPnl: nil,
            mostTradedSymbol: mostTradedTicker(trades),
            averageHoldTimeSeconds: averageHoldSeconds(trades)
        )
    }

    private static func pnl(_ trade: Trade) -> Double {
        NSDecimalNumber(decimal: trade.realizedPnL?.amount ?? 0).doubleValue
    }

    private static func averageRr(_ trades: [Trade]) -> Double? {
        let values = trades.compactMap { trade -> Double? in
            guard let rr = trade.riskReward else { return nil }
            return NSDecimalNumber(decimal: rr).doubleValue
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func computeProfitFactor(_ trades: [Trade]) -> Double? {
        let grossProfit = trades.filter { pnl($0) > 0 }.reduce(0.0) { $0 + pnl($1) }
        let grossLoss = trades.filter { pnl($0) < 0 }.reduce(0.0) { $0 + abs(pnl($1)) }
        guard grossLoss > 0 else { return nil }
        return grossProfit / grossLoss
    }

    private static func computeDailyPnl(_ trades: [Trade]) -> [String: Decimal] {
        var map: [String: Decimal] = [:]
        for trade in trades {
            guard let key = TradingCalendarDay.key(for: trade) else { continue }
            map[key, default: 0] += trade.realizedPnL?.amount ?? 0
        }
        return map
    }

    private enum ExtremeMode { case best, worst }

    private static func pickExtremeDay(
        _ daily: [String: Decimal],
        mode: ExtremeMode,
        calendar: Calendar
    ) -> (label: String?, pnl: Decimal?) {
        guard !daily.isEmpty else { return (nil, nil) }
        let picked: (key: String, pnl: Decimal)? = {
            switch mode {
            case .best: return daily.max(by: { $0.value < $1.value }).map { ($0.key, $0.value) }
            case .worst: return daily.min(by: { $0.value < $1.value }).map { ($0.key, $0.value) }
            }
        }()
        guard let picked else { return (nil, nil) }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
        if let parts = picked.key.split(separator: "-").compactMap({ Int($0) }) as [Int]?,
           parts.count == 3,
           let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) {
            return (formatter.string(from: date), picked.pnl)
        }
        return (picked.key, picked.pnl)
    }

    private static func mostTradedTicker(_ trades: [Trade]) -> String? {
        var counts: [String: Int] = [:]
        for trade in trades {
            let key = trade.symbol.ticker.uppercased()
            guard !key.isEmpty else { continue }
            counts[key, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    private static func averageHoldSeconds(_ trades: [Trade]) -> Int? {
        let durations: [TimeInterval] = trades.compactMap { trade in
            guard let exit = trade.exitAt else { return nil }
            let seconds = exit.timeIntervalSince(trade.entryAt)
            return seconds > 0 ? seconds : nil
        }
        guard !durations.isEmpty else { return nil }
        let avg = durations.reduce(0, +) / Double(durations.count)
        return Int(avg.rounded())
    }
}
