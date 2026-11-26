import Foundation

/// Yearly + month drill-down Performance Reports, reuses ``DashboardChartMetrics``.
nonisolated enum TradingYearlyReportGenerator {
    private static func reportScope(
        filters: TradingReportFilters,
        interval: DateInterval,
        copyTradingGroups: [CopyTradingGroup]
    ) -> DashboardClientScopeFilter {
        DashboardClientScopeFilter(
            accountFilter: filters.accountFilter,
            dateRange: .all,
            customInterval: interval,
            accountMode: filters.accountMode,
            showPublicOnly: false,
            copyTradingGroups: copyTradingGroups
        )
    }

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
        copyTradingGroups: [CopyTradingGroup] = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TradingYearlyReport {
        let bounds = TradingReportPeriods.yearBounds(year: year, now: now, calendar: calendar)
        let interval = DateInterval(start: bounds.start, end: bounds.end)
        let inputs = trades.map {
            DashboardChartMetrics.Input(trade: $0, accountType: nil)
        }
        let scope = reportScope(
            filters: filters,
            interval: interval,
            copyTradingGroups: copyTradingGroups
        )
        let scopedTrades = DashboardChartMetrics.filteredTrades(
            from: inputs,
            scope: scope,
            now: now
        )
        let summary = DashboardChartMetrics.compute(
            from: inputs,
            scope: scope,
            payoutTotal: nil,
            now: now
        )

        let metrics = TradingReportGeneratorMetricsBridge.buildMetrics(
            from: scopedTrades,
            includeSessionExtremes: true
        )

        let monthRows = buildMonthRows(
            year: year,
            trades: trades,
            filters: filters,
            copyTradingGroups: copyTradingGroups,
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
        copyTradingGroups: [CopyTradingGroup] = [],
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
        let scope = reportScope(
            filters: filters,
            interval: interval,
            copyTradingGroups: copyTradingGroups
        )
        let scopedTrades = DashboardChartMetrics.filteredTrades(
            from: inputs,
            scope: scope,
            now: now
        )
        let metrics = TradingReportGeneratorMetricsBridge.buildMetrics(
            from: scopedTrades,
            includeSessionExtremes: true
        )

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
        copyTradingGroups: [CopyTradingGroup],
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
            let scope = reportScope(
                filters: filters,
                interval: interval,
                copyTradingGroups: copyTradingGroups
            )
            let summary = DashboardChartMetrics.compute(
                from: inputs,
                scope: scope,
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
        metrics: TradingReportMetrics,
        year: Int
    ) -> String {
        if metrics.tradesTaken == 0 {
            return "No trades matched your filters during \(year)."
        }
        guard metrics.knownResultCount > 0 else {
            return "\(year) has \(NumberDisplay.integer(metrics.tradesTaken)) trades, but none have a P&L yet."
        }

        let tone: String = {
            if metrics.netPnl > 0 { return "positive" }
            if metrics.netPnl < 0 { return "negative" }
            return "flat"
        }()

        let winRateText = NumberDisplay.percent(
            metrics.winRate,
            minimumFractionDigits: 1,
            maximumFractionDigits: 1
        ) + " win rate"

        let winningDays = metrics.winningDays ?? 0
        let losingDays = metrics.losingDays ?? 0
        return "\(year) was a \(tone) year with \(NumberDisplay.integer(metrics.tradesTaken)) trades and \(formatPnl(metrics.netPnl)) net P&L. You finished with \(winRateText) across \(NumberDisplay.integer(winningDays)) winning days and \(NumberDisplay.integer(losingDays)) losing days."
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

/// Bridges scoped trades into ``TradingReportMetrics`` (weekly, monthly, yearly, custom).
nonisolated enum TradingReportGeneratorMetricsBridge {
    static func buildMetrics(
        from trades: [Trade],
        includeSessionExtremes: Bool = false
    ) -> TradingReportMetrics {
        let pricedAmounts = trades.compactMap { $0.realizedPnL?.amount }
        let pricedDoubles = pricedAmounts.map { NSDecimalNumber(decimal: $0).doubleValue }
        let wins = pricedDoubles.filter { $0 > 0 }
        let losses = pricedDoubles.filter { $0 < 0 }
        let winRate = pricedDoubles.isEmpty ? 0 : (Double(wins.count) / Double(pricedDoubles.count)) * 100
        let totalPnL = pricedDoubles.reduce(0, +)

        let avgWinner: Double? = {
            guard !wins.isEmpty else { return nil }
            return wins.reduce(0, +) / Double(wins.count)
        }()
        let avgLoser: Double? = {
            guard !losses.isEmpty else { return nil }
            return losses.reduce(0, +) / Double(losses.count)
        }()
        let lossRate = pricedDoubles.isEmpty ? 0 : Double(losses.count) / Double(pricedDoubles.count)
        let winRateFrac = pricedDoubles.isEmpty ? 0 : Double(wins.count) / Double(pricedDoubles.count)
        let expectancy: Double? = {
            guard !pricedDoubles.isEmpty else { return nil }
            return winRateFrac * (avgWinner ?? 0) + lossRate * (avgLoser ?? 0)
        }()

        let daily = computeDailyPnl(trades)
        let bestDay = pickExtremeDay(daily, mode: .best)
        let worstDay = pickExtremeDay(daily, mode: .worst)
        let sameDay = bestDay.label != nil && bestDay.label == worstDay.label
        let winningDays = daily.isEmpty ? nil : daily.values.filter { $0 > 0 }.count
        let losingDays = daily.isEmpty ? nil : daily.values.filter { $0 < 0 }.count

        let bestSession: (label: String?, pnl: Double?)
        let worstSession: (label: String?, pnl: Double?)
        if includeSessionExtremes {
            let sessions = computeSessionPnl(trades)
            bestSession = pickExtremeSession(sessions, mode: .best)
            worstSession = pickExtremeSession(sessions, mode: .worst)
        } else {
            bestSession = (nil, nil)
            worstSession = (nil, nil)
        }

        return TradingReportMetrics(
            netPnl: totalPnL,
            winRate: winRate,
            knownResultCount: pricedDoubles.count,
            averageRr: averageTargetRr(trades),
            averageReachedRr: averageReachedRr(trades),
            profitFactor: computeProfitFactor(pricedDoubles),
            tradesTaken: trades.count,
            averageWinner: avgWinner,
            averageLoser: avgLoser,
            expectancy: expectancy,
            bestTrade: wins.max(),
            worstTrade: losses.min(),
            maxDrawdown: maxDrawdownAmount(trades),
            bestDayLabel: sameDay ? nil : bestDay.label,
            bestDayPnl: sameDay ? nil : bestDay.pnl,
            worstDayLabel: sameDay ? nil : worstDay.label,
            worstDayPnl: sameDay ? nil : worstDay.pnl,
            winningDays: winningDays,
            losingDays: losingDays,
            bestSessionLabel: bestSession.label,
            bestSessionPnl: bestSession.pnl,
            worstSessionLabel: worstSession.label,
            worstSessionPnl: worstSession.pnl,
            mostTradedSymbol: mostTradedTicker(trades),
            averageHoldTimeSeconds: averageHoldSeconds(trades)
        )
    }

    private static func knownPnl(_ trade: Trade) -> Double? {
        guard let amount = trade.realizedPnL?.amount else { return nil }
        return NSDecimalNumber(decimal: amount).doubleValue
    }

    private static func averageTargetRr(_ trades: [Trade]) -> Double? {
        guard let average = TradePointsAndRealizedRr.averageTargetedRr(trades: trades) else { return nil }
        return NSDecimalNumber(decimal: average).doubleValue
    }

    private static func averageReachedRr(_ trades: [Trade]) -> Double? {
        guard let average = TradePointsAndRealizedRr.averageMaxRrReached(trades: trades) else { return nil }
        return NSDecimalNumber(decimal: average).doubleValue
    }

    private static func computeProfitFactor(_ priced: [Double]) -> Double? {
        let grossProfit = priced.filter { $0 > 0 }.reduce(0, +)
        let grossLoss = priced.filter { $0 < 0 }.reduce(0) { $0 + abs($1) }
        guard grossLoss > 0 else { return nil }
        return grossProfit / grossLoss
    }

    private static func maxDrawdownAmount(_ trades: [Trade]) -> Double? {
        let chronological = trades.sorted {
            ($0.exitAt ?? $0.entryAt) < ($1.exitAt ?? $1.entryAt)
        }
        var running: Decimal = 0
        var peak: Decimal = 0
        var maxDD: Decimal = 0
        var hasPriced = false
        for trade in chronological {
            guard let amount = trade.realizedPnL?.amount else { continue }
            hasPriced = true
            running += amount
            if running > peak { peak = running }
            let drawdown = peak - running
            if drawdown > maxDD { maxDD = drawdown }
        }
        guard hasPriced else { return nil }
        return NSDecimalNumber(decimal: maxDD).doubleValue
    }

    private struct PricedBucket {
        var pnl: Double = 0
        var count: Int = 0
    }

    private static func computeDailyPnl(_ trades: [Trade]) -> [String: Double] {
        var map: [String: Double] = [:]
        for trade in trades {
            let key = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: trade)
            guard !key.isEmpty, let value = knownPnl(trade) else { continue }
            map[key, default: 0] += value
        }
        return map
    }

    private enum ExtremeMode { case best, worst }

    private static func pickExtremeDay(
        _ daily: [String: Double],
        mode: ExtremeMode
    ) -> (label: String?, pnl: Double?) {
        guard daily.count >= 2 else { return (nil, nil) }
        let eligible = daily.filter { mode == .best ? $0.value > 0 : $0.value < 0 }
        guard let picked = (mode == .best
            ? eligible.max(by: { $0.value < $1.value })
            : eligible.min(by: { $0.value < $1.value }))
        else { return (nil, nil) }
        let opposite = daily.values.contains { mode == .best ? $0 < picked.value : $0 > picked.value }
        guard opposite else { return (nil, nil) }
        let calendar = TradingReportPeriods.eastern
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
        if let date = dayKeyDate(picked.key, calendar: calendar) {
            return (formatter.string(from: date), picked.value)
        }
        return (picked.key, picked.value)
    }

    private static func dayKeyDate(_ key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: parts[0],
            month: parts[1],
            day: parts[2],
            hour: 12
        ))
    }

    private static func computeSessionPnl(_ trades: [Trade]) -> [String: PricedBucket] {
        var map: [String: PricedBucket] = [:]
        for trade in trades {
            guard let bucket = macroSessionBucket(for: trade) else { continue }
            guard let value = knownPnl(trade) else { continue }
            var row = map[bucket] ?? PricedBucket()
            row.pnl += value
            row.count += 1
            map[bucket] = row
        }
        return map
    }

    private static func pickExtremeSession(
        _ sessions: [String: PricedBucket],
        mode: ExtremeMode
    ) -> (label: String?, pnl: Double?) {
        let rows = sessions.filter { $0.value.count >= 1 }
        guard !rows.isEmpty else { return (nil, nil) }

        if rows.count == 1 {
            guard mode == .best, let only = rows.first else { return (nil, nil) }
            return (macroSessionDisplayTitle(only.key), only.value.pnl)
        }

        guard let picked = (mode == .best
            ? rows.max(by: { $0.value.pnl < $1.value.pnl })
            : rows.min(by: { $0.value.pnl < $1.value.pnl }))
        else { return (nil, nil) }

        if mode == .worst {
            let bestKey = rows.max(by: { $0.value.pnl < $1.value.pnl })?.key
            if bestKey == picked.key { return (nil, nil) }
        }

        return (macroSessionDisplayTitle(picked.key), picked.value.pnl)
    }

    private static func macroSessionBucket(for trade: Trade) -> String? {
        let fine = normalizeSessionBucket(trade.sessionLabel)
            ?? TradingSessionLabel.session(from: trade.entryAt)
        guard let fine else { return nil }
        return rollupMacroSessionKey(fine)
    }

    private static func rollupMacroSessionKey(_ fine: String) -> String {
        switch fine {
        case "NY AM", "NY Lunch", "NY PM", "After":
            return "NY"
        default:
            return fine
        }
    }

    private static func macroSessionDisplayTitle(_ key: String) -> String {
        switch key {
        case "NY": return "New York"
        case "London": return "London"
        case "Asia": return "Asia"
        default: return TradingSessionCatalog.displayTitle(for: key)
        }
    }

    private static func normalizeSessionBucket(_ raw: String?) -> String? {
        TradingSessionLabel.canonicalLabel(fromStored: raw)
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
