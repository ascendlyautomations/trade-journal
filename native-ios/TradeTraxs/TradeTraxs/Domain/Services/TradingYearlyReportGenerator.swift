import Foundation

/// Yearly + month drill-down Performance Reports, reuses ``DashboardChartMetrics``.
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
        let sameDay = bestDay.label != nil && bestDay.label == worstDay.label
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
            bestDayLabel: sameDay ? nil : bestDay.label,
            bestDayPnl: sameDay ? nil : bestDay.pnl,
            worstDayLabel: sameDay ? nil : worstDay.label,
            worstDayPnl: sameDay ? nil : worstDay.pnl,
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

    /// Month drill-down, same filters and trade scope as yearly reports.
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
        let currentYear = TradingReportPeriods.eastern.component(.year, from: now)
        let currentMonth = TradingReportPeriods.eastern.component(.month, from: now)
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
            return "No trades matched your filters during \(year)."
        }
        guard metrics.winRate != nil else {
            return "\(year) has \(NumberDisplay.integer(metrics.tradeCount)) trades, but none have a P&L yet."
        }

        let tone: String = {
            if metrics.netPnl > 0 { return "positive" }
            if metrics.netPnl < 0 { return "negative" }
            return "flat"
        }()

        let winRateText: String = {
            guard let winRate = metrics.winRate else { return "no closed trades" }
            return "\(NumberDisplay.percent(winRate * 100, minimumFractionDigits: 1, maximumFractionDigits: 1)) win rate"
        }()

        return "\(year) was a \(tone) year with \(NumberDisplay.integer(metrics.tradeCount)) trades and \(formatMoney(metrics.netPnl)) net P&L. You finished with \(winRateText) across \(NumberDisplay.integer(metrics.winningDays)) winning days and \(NumberDisplay.integer(metrics.losingDays)) losing days."
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
        if metrics.knownResultCount == 0 {
            return "\(label) \(ref.year): \(NumberDisplay.integer(metrics.tradesTaken)) trades, but none have a P&L yet."
        }
        return "\(label) \(ref.year): \(formatPnl(metrics.netPnl)) across \(NumberDisplay.integer(metrics.knownResultCount)) priced trades."
    }

    private static func buildMonthKeyTakeaway(metrics: TradingReportMetrics) -> String {
        if metrics.tradesTaken == 0 {
            return "This month had no matching trades for your active filters."
        }
        if metrics.knownResultCount == 0 {
            return "P&L is missing on these trades, so this month does not estimate a result."
        }
        if metrics.netPnl > 0 {
            return "The month finished net positive."
        }
        if metrics.netPnl < 0 {
            return "The month finished net negative."
        }
        return "The month finished flat."
    }

    // MARK: - Helpers

    private enum ExtremeMode { case best, worst }

    private static func computeDailyPnl(_ trades: [Trade], calendar: Calendar) -> [String: Decimal] {
        var map: [String: Decimal] = [:]
        for trade in trades {
            let key = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: trade)
            guard !key.isEmpty, let amount = trade.realizedPnL?.amount else { continue }
            map[key, default: 0] += amount
        }
        return map
    }

    private static func pickExtremeDay(
        _ daily: [String: Decimal],
        mode: ExtremeMode,
        calendar: Calendar
    ) -> (label: String?, pnl: Decimal?) {
        _ = calendar
        guard daily.count >= 2 else { return (nil, nil) }
        let eligible = daily.filter { mode == .best ? $0.value > 0 : $0.value < 0 }
        let picked: (key: String, pnl: Decimal)? = {
            switch mode {
            case .best: return eligible.max(by: { $0.value < $1.value }).map { ($0.key, $0.value) }
            case .worst: return eligible.min(by: { $0.value < $1.value }).map { ($0.key, $0.value) }
            }
        }()
        guard let picked else { return (nil, nil) }
        let opposite = daily.values.contains { mode == .best ? $0 < picked.pnl : $0 > picked.pnl }
        guard opposite else { return (nil, nil) }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = TradingReportPeriods.eastern.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
        if let date = dayKeyDate(picked.key) {
            return (formatter.string(from: date), picked.pnl)
        }
        return (picked.key, picked.pnl)
    }

    private static func findBestTradeID(_ trades: [Trade]) -> String? {
        trades.max(by: {
            (knownAmount($0) ?? -.greatestFiniteMagnitude) < (knownAmount($1) ?? -.greatestFiniteMagnitude)
        }).flatMap { trade in
            guard let amount = knownAmount(trade), amount > 0 else { return nil }
            return trade.id.rawValue
        }
    }

    private static func knownAmount(_ trade: Trade) -> Double? {
        guard let amount = trade.realizedPnL?.amount else { return nil }
        return NSDecimalNumber(decimal: amount).doubleValue
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
        return TradingReportPeriods.eastern.date(from: DateComponents(
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
        NumberDisplay.reportPnL(value)
    }

    private static func formatPnl(_ value: Double) -> String {
        NumberDisplay.reportPnL(value)
    }
}

/// Bridges scoped trades into ``TradingReportMetrics`` for month drill-down reuse.
nonisolated enum TradingReportGeneratorMetricsBridge {
    static func buildMetrics(from trades: [Trade], calendar: Calendar = .current) -> TradingReportMetrics {
        let totalTrades = trades.count
        let priced = trades.compactMap { $0.realizedPnL?.amount }
        let wins = priced.filter { $0 > 0 }.count
        let winRate = priced.isEmpty ? 0 : (Double(wins) / Double(priced.count)) * 100
        let totalPnL = priced.reduce(Decimal(0), +)
        let daily = computeDailyPnl(trades)
        let bestDay = pickExtremeDay(daily, mode: .best, calendar: calendar)
        let worstDay = pickExtremeDay(daily, mode: .worst, calendar: calendar)
        let sameDay = bestDay.label != nil && bestDay.label == worstDay.label

        return TradingReportMetrics(
            netPnl: NSDecimalNumber(decimal: totalPnL).doubleValue,
            winRate: winRate,
            knownResultCount: trades.compactMap { $0.realizedPnL?.amount }.count,
            averageRr: averageRr(trades),
            profitFactor: computeProfitFactor(trades),
            tradesTaken: totalTrades,
            bestDayLabel: sameDay ? nil : bestDay.label,
            bestDayPnl: sameDay ? nil : bestDay.pnl.map { NSDecimalNumber(decimal: $0).doubleValue },
            worstDayLabel: sameDay ? nil : worstDay.label,
            worstDayPnl: sameDay ? nil : worstDay.pnl.map { NSDecimalNumber(decimal: $0).doubleValue },
            bestSessionLabel: nil,
            bestSessionPnl: nil,
            worstSessionLabel: nil,
            worstSessionPnl: nil,
            mostTradedSymbol: mostTradedTicker(trades),
            averageHoldTimeSeconds: averageHoldSeconds(trades)
        )
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
        let values = trades.compactMap { $0.realizedPnL?.amount }
        let grossProfit = values.filter { $0 > 0 }.reduce(Decimal(0), +)
        let grossLoss = values.filter { $0 < 0 }.reduce(Decimal(0)) { $0 + abs($1) }
        guard grossLoss > 0 else { return nil }
        return NSDecimalNumber(decimal: grossProfit / grossLoss).doubleValue
    }

    private static func computeDailyPnl(_ trades: [Trade]) -> [String: Decimal] {
        var map: [String: Decimal] = [:]
        for trade in trades {
            let key = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: trade)
            guard !key.isEmpty, let amount = trade.realizedPnL?.amount else { continue }
            map[key, default: 0] += amount
        }
        return map
    }

    private enum ExtremeMode { case best, worst }

    private static func pickExtremeDay(
        _ daily: [String: Decimal],
        mode: ExtremeMode,
        calendar: Calendar
    ) -> (label: String?, pnl: Decimal?) {
        guard daily.count >= 2 else { return (nil, nil) }
        let eligible = daily.filter { mode == .best ? $0.value > 0 : $0.value < 0 }
        let picked: (key: String, pnl: Decimal)? = {
            switch mode {
            case .best: return eligible.max(by: { $0.value < $1.value }).map { ($0.key, $0.value) }
            case .worst: return eligible.min(by: { $0.value < $1.value }).map { ($0.key, $0.value) }
            }
        }()
        guard let picked else { return (nil, nil) }
        let opposite = daily.values.contains { mode == .best ? $0 < picked.pnl : $0 > picked.pnl }
        guard opposite else { return (nil, nil) }
        let calendar = TradingReportPeriods.eastern
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = calendar.timeZone
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
