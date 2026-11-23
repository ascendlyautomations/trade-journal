import Foundation

/// Web `lib/tradingReports/generateTradingReport.ts` — deterministic report builder.
///
/// iOS consumes the same rules/copy as web. No separate AI prompts or BFF generate route.
nonisolated enum TradingReportGenerator {
    private static let weekdayLabels = [
        "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
    ]

    static func generateAll(
        trades: [Trade],
        now: Date = Date(),
        preferences: PreferenceRuleContext? = nil
    ) -> [TradingReportPeriodKey: TradingReport] {
        var result: [TradingReportPeriodKey: TradingReport] = [:]
        for key in TradingReportPeriodKey.allCases {
            result[key] = generate(trades: trades, periodKey: key, now: now, preferences: preferences)
        }
        return result
    }

    static func generate(
        trades: [Trade],
        periodKey: TradingReportPeriodKey,
        now: Date = Date(),
        preferences: PreferenceRuleContext? = nil
    ) -> TradingReport {
        let bounds = TradingReportPeriods.bounds(for: periodKey, now: now)
        return generate(trades: trades, bounds: bounds, now: now, preferences: preferences)
    }

    static func generate(
        trades: [Trade],
        week: TradingReportWeekRef,
        now: Date = Date(),
        preferences: PreferenceRuleContext? = nil
    ) -> TradingReport {
        let bounds = TradingReportPeriods.bounds(forWeekStarting: week.mondayKey, now: now)
            ?? TradingReportPeriods.bounds(for: .weeklyThis, now: now)
        return generate(trades: trades, bounds: bounds, now: now, preferences: preferences)
    }

    /// Custom performance report — same narrative engine, filtered by active report filters.
    static func generateCustomRange(
        trades: [Trade],
        interval: DateInterval,
        filters: TradingReportFilters,
        now: Date = Date(),
        preferences: PreferenceRuleContext? = nil
    ) -> TradingReport {
        let inputs = trades.map { DashboardChartMetrics.Input(trade: $0, accountType: nil) }
        let scoped = DashboardChartMetrics.filteredTrades(
            from: inputs,
            accountFilter: filters.accountFilter,
            accountMode: filters.accountMode,
            interval: interval,
            now: now
        )
        let bounds = TradingReportPeriods.customBounds(interval: interval)
        return generate(trades: scoped, bounds: bounds, now: now, preferences: preferences)
    }

    private static func generate(
        trades: [Trade],
        bounds: TradingReportPeriods.Bounds,
        now: Date,
        preferences: PreferenceRuleContext?
    ) -> TradingReport {
        let periodKey = bounds.key
        _ = now
        let periodTrades = filterTrades(trades, bounds: bounds)
        let metrics = buildMetrics(periodTrades)

        let comparisonTrades = comparablePriorTrades(trades, periodKey: periodKey, bounds: bounds)
        let partial = bounds.kind != .custom && !partialSuffix(for: periodKey, bounds: bounds).isEmpty

        let strengths = buildStrengths(periodTrades, metrics: metrics, comparisonTrades: comparisonTrades)
        let adjustment = ruleAdjustment(periodTrades, preferences: preferences)
            ?? buildOpportunities(periodTrades, metrics: metrics).first
        let recommendations = adjustment.map { [$0] } ?? []
        let bestTrade = findBestTrade(periodTrades)
        let changed = whatChanged(metrics: metrics, prior: comparisonTrades)

        return TradingReport(
            periodKey: periodKey,
            kind: bounds.kind,
            title: bounds.kind.title,
            dateRangeLabel: TradingReportPeriods.dateRangeLabel(
                start: bounds.start,
                end: bounds.end,
                kind: bounds.kind
            ) + partialSuffix(for: periodKey, bounds: bounds),
            periodStartIso: isoString(bounds.start),
            periodEndIso: isoString(bounds.end),
            generatedAt: now.timeIntervalSince1970 * 1000,
            executiveSummary: buildExecutiveSummary(
                metrics: metrics,
                kind: bounds.kind,
                partial: partial,
                comparisonNote: comparisonAvailabilityNote(periodTrades, comparisonTrades),
                changedNote: changed
            ),
            metrics: metrics,
            strengths: strengths,
            opportunities: [],
            recommendations: recommendations,
            bestTradeId: bestTrade.map(\.id.rawValue),
            keyTakeaway: buildKeyTakeaway(
                metrics: metrics,
                adjustment: adjustment,
                kind: bounds.kind
            ),
            summarySource: "deterministic"
        )
    }

    // MARK: - Filtering

    private static func filterTrades(_ trades: [Trade], bounds: TradingReportPeriods.Bounds) -> [Trade] {
        let startKey = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: bounds.start)
        let endKey = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: bounds.end)
        return trades.filter { trade in
            let key = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: trade)
            return !key.isEmpty && key >= startKey && key <= endKey
        }
    }

    private static func resolveTimeSource(_ trade: Trade) -> Date {
        trade.entryAt
    }

    // MARK: - Metrics

    private static func buildMetrics(_ trades: [Trade]) -> TradingReportMetrics {
        let priced = trades.compactMap { knownPnl($0) }
        let wins = priced.filter { $0 > 0 }.count
        let winRate = priced.isEmpty ? 0 : (Double(wins) / Double(priced.count)) * 100
        let totalPnL = priced.reduce(0, +)
        let avgRR = averageRr(trades)
        let daily = computeDailyPnl(trades)
        let sessions = computeSessionPnl(trades)
        let bestDay = pickExtremeDay(daily, mode: .best)
        let worstDay = pickExtremeDay(daily, mode: .worst)
        let bestSession = pickExtremeSession(sessions, mode: .best)
        let worstSession = pickExtremeSession(sessions, mode: .worst)
        let sameDay = bestDay.label != nil && bestDay.label == worstDay.label

        return TradingReportMetrics(
            netPnl: totalPnL,
            winRate: winRate,
            knownResultCount: priced.count,
            averageRr: avgRR,
            profitFactor: computeProfitFactor(trades),
            tradesTaken: trades.count,
            bestDayLabel: sameDay ? nil : bestDay.label,
            bestDayPnl: sameDay ? nil : bestDay.pnl,
            worstDayLabel: sameDay ? nil : worstDay.label,
            worstDayPnl: sameDay ? nil : worstDay.pnl,
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

    private static func partialSuffix(
        for key: TradingReportPeriodKey,
        bounds: TradingReportPeriods.Bounds
    ) -> String {
        if bounds.kind == .custom { return "" }
        let calendar = TradingReportPeriods.eastern
        switch key {
        case .weeklyThis:
            let sunday = calendar.date(byAdding: .day, value: 6, to: bounds.start) ?? bounds.end
            return calendar.isDate(bounds.end, inSameDayAs: sunday) ? "" : " (partial)"
        case .monthlyThis:
            let day = calendar.component(.day, from: bounds.end)
            let length = calendar.range(of: .day, in: .month, for: bounds.start)?.count ?? day
            return day < length ? " (partial)" : ""
        case .weeklyLast, .monthlyLast:
            return ""
        }
    }

    private static func comparablePriorTrades(
        _ trades: [Trade],
        periodKey: TradingReportPeriodKey,
        bounds: TradingReportPeriods.Bounds
    ) -> [Trade]? {
        if bounds.kind == .custom { return nil }
        let calendar = TradingReportPeriods.eastern
        let prior: (Date, Date)?
        switch periodKey {
        case .weeklyThis:
            guard let start = calendar.date(byAdding: .day, value: -7, to: bounds.start),
                  let end = calendar.date(byAdding: .day, value: -7, to: bounds.end)
            else { return nil }
            prior = (start, end)
        case .monthlyThis:
            guard let start = calendar.date(byAdding: .month, value: -1, to: bounds.start),
                  let end = calendar.date(byAdding: .month, value: -1, to: bounds.end)
            else { return nil }
            prior = (start, end)
        case .weeklyLast, .monthlyLast:
            return nil
        }
        guard let prior else { return nil }
        return trades.filter { trade in
            let key = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: trade)
            let startKey = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: prior.0)
            let endKey = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: prior.1)
            return key >= startKey && key <= endKey
        }
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
        let values = trades.compactMap { knownPnl($0) }
        let grossProfit = values.filter { $0 > 0 }.reduce(0, +)
        let grossLoss = values.filter { $0 < 0 }.reduce(0) { $0 + abs($1) }
        guard grossLoss > 0 else { return nil }
        return grossProfit / grossLoss
    }

    private struct PricedBucket {
        var pnl: Double = 0
        var count: Int = 0
    }

    private static let comparativeMinimum = 5

    private static func computeDailyPnl(_ trades: [Trade]) -> [String: PricedBucket] {
        var map: [String: PricedBucket] = [:]
        for trade in trades {
            let key = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: trade)
            guard !key.isEmpty, let value = knownPnl(trade) else { continue }
            var row = map[key] ?? PricedBucket()
            row.pnl += value
            row.count += 1
            map[key] = row
        }
        return map
    }

    private static func pickExtremeDay(
        _ daily: [String: PricedBucket],
        mode: ExtremeMode
    ) -> (label: String?, pnl: Double?) {
        guard daily.count >= 2 else { return (nil, nil) }
        let eligible = daily.filter { mode == .best ? $0.value.pnl > 0 : $0.value.pnl < 0 }
        guard let picked = (mode == .best
            ? eligible.max(by: { $0.value.pnl < $1.value.pnl })
            : eligible.min(by: { $0.value.pnl < $1.value.pnl }))
        else { return (nil, nil) }
        let opposite = daily.values.contains { mode == .best ? $0.pnl < picked.value.pnl : $0.pnl > picked.value.pnl }
        guard opposite else { return (nil, nil) }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = TradingReportPeriods.eastern.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
        if let date = dayKeyDate(picked.key) {
            return (formatter.string(from: date), picked.value.pnl)
        }
        return (picked.key, picked.value.pnl)
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
            ?? TradingSessionLabel.session(from: resolveTimeSource(trade))
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

    // MARK: - Narrative (web template copy)

    private static func buildExecutiveSummary(
        metrics: TradingReportMetrics,
        kind: TradingReportKind,
        partial: Bool,
        comparisonNote: String?,
        changedNote: String? = nil
    ) -> String {
        let periodLabel = periodNoun(for: kind)
        let partialLabel = partial ? "partial " : ""
        if metrics.tradesTaken == 0 {
            return "No trades were logged during this \(partialLabel)\(periodLabel)."
        }
        if metrics.knownResultCount == 0 {
            let tradeWord = metrics.tradesTaken == 1 ? "trade" : "trades"
            return "\(NumberDisplay.integer(metrics.tradesTaken)) \(tradeWord) were logged this \(partialLabel)\(periodLabel), but none have a P&L yet."
        }
        let tone = metrics.netPnl > 0 ? "positive" : metrics.netPnl < 0 ? "negative" : "flat"
        let priced = metrics.knownResultCount == metrics.tradesTaken
            ? "\(NumberDisplay.integer(metrics.tradesTaken)) trade\(metrics.tradesTaken == 1 ? "" : "s")"
            : "\(NumberDisplay.integer(metrics.knownResultCount)) priced trade\(metrics.knownResultCount == 1 ? "" : "s") of \(NumberDisplay.integer(metrics.tradesTaken))"
        let winRate = metrics.knownResultCount >= comparativeMinimum
            ? " Win rate was \(NumberDisplay.percent(metrics.winRate, minimumFractionDigits: 1, maximumFractionDigits: 1))."
            : ""
        let comparison = comparisonNote.map { " \($0)" } ?? ""
        let changed = changedNote.map { " \($0)" } ?? ""
        return "This \(partialLabel)\(periodLabel) was \(tone): \(formatPnl(metrics.netPnl)) across \(priced).\(winRate)\(comparison)\(changed)"
    }

    private static func comparisonAvailabilityNote(
        _ current: [Trade],
        _ prior: [Trade]?
    ) -> String? {
        guard let prior else { return nil }
        let currentPriced = current.compactMap { knownPnl($0) }.count
        let priorPriced = prior.compactMap { knownPnl($0) }.count
        if currentPriced >= comparativeMinimum, priorPriced >= comparativeMinimum { return nil }
        return "A same-window comparison with the prior period is not available yet."
    }

    private static func buildStrengths(
        _ trades: [Trade],
        metrics: TradingReportMetrics,
        comparisonTrades: [Trade]?
    ) -> [String] {
        var strengths: [String] = []

        if let label = metrics.bestSessionLabel,
           let sessionPnl = metrics.bestSessionPnl,
           sessionPnl > 0 {
            strengths.append("\(label) was ahead of your other sessions (\(formatPnl(sessionPnl))).")
        }

        if let pf = metrics.profitFactor, pf >= 1.5, metrics.knownResultCount >= comparativeMinimum {
            strengths.append("Profit factor was \(NumberDisplay.ratio(pf, fractionDigits: 2)).")
        }

        if let comparisonTrades,
           comparisonTrades.compactMap({ knownPnl($0) }).count >= comparativeMinimum,
           metrics.knownResultCount >= comparativeMinimum,
           let current = metrics.averageRr,
           let prior = averageRr(comparisonTrades),
           prior != 0,
           current > prior * 1.05 {
            let pct = Int((((current - prior) / abs(prior)) * 100).rounded())
            strengths.append("Average R was \(NumberDisplay.integer(pct))% higher than the same window in the prior period.")
        }

        let strategies = computeStrategyPnl(trades).filter { $0.value.count >= comparativeMinimum && $0.value.pnl > 0 }
        if strategies.count >= 2, let best = strategies.max(by: { $0.value.pnl < $1.value.pnl }) {
            strengths.append("\(best.key) was your strongest tagged setup (\(formatPnl(best.value.pnl))).")
        }

        return Array(strengths.prefix(3))
    }

    private static func buildOpportunities(
        _ trades: [Trade],
        metrics: TradingReportMetrics
    ) -> [String] {
        var opportunities: [String] = []

        if let label = metrics.worstSessionLabel,
           let sessionPnl = metrics.worstSessionPnl,
           sessionPnl < 0,
           label != metrics.bestSessionLabel {
            opportunities.append("\(label) was behind your other sessions (\(formatPnl(sessionPnl))).")
        }

        let hourly = computeHourlyPnl(trades)
        var morning = PricedBucket()
        var afternoon = PricedBucket()
        for (hour, row) in hourly {
            if hour >= 12 {
                afternoon.pnl += row.pnl
                afternoon.count += row.count
            } else {
                morning.pnl += row.pnl
                morning.count += row.count
            }
        }
        if morning.count >= comparativeMinimum,
           afternoon.count >= comparativeMinimum,
           afternoon.pnl < morning.pnl,
           afternoon.pnl < 0 {
            opportunities.append("Afternoon results were weaker than the morning.")
        }

        let weekdays = computeWeekdayPnl(trades).filter { $0.value.count >= comparativeMinimum }
        if weekdays.count >= 2, let worst = weekdays.min(by: { $0.value.pnl < $1.value.pnl }), worst.value.pnl < 0,
           worst.key >= 0, worst.key < weekdayLabels.count {
            opportunities.append(
                "\(weekdayLabels[worst.key]) was the weakest weekday with at least \(comparativeMinimum) priced trades (\(formatPnl(worst.value.pnl)))."
            )
        }

        if let average = metrics.averageRr, average < 1, metrics.knownResultCount >= comparativeMinimum {
            opportunities.append("Average R was \(formatRR(average)).")
        }

        if let pf = metrics.profitFactor, pf < 1, metrics.knownResultCount >= comparativeMinimum {
            opportunities.append(
                "Profit factor was \(NumberDisplay.ratio(pf, fractionDigits: 2)). Losses exceeded gains."
            )
        }

        let hourlyRows = hourly.filter { $0.value.count >= comparativeMinimum }
        if hourlyRows.count >= 2, let worstHour = hourlyRows.min(by: { $0.value.pnl < $1.value.pnl }), worstHour.value.pnl < 0 {
            opportunities.append(
                "\(formatHourLabel(worstHour.key)) Eastern was the weakest hour with at least \(comparativeMinimum) priced trades."
            )
        }

        return Array(opportunities.prefix(5))
    }

    private static func buildKeyTakeaway(
        metrics: TradingReportMetrics,
        adjustment: String?,
        kind: TradingReportKind
    ) -> String {
        let periodLabel = periodNoun(for: kind)
        if metrics.tradesTaken == 0 {
            return "No trades were logged this \(periodLabel)."
        }
        if metrics.knownResultCount == 0 {
            return "P&L is missing on these trades, so this report does not estimate a result."
        }
        if let adjustment { return adjustment }
        return "\(formatPnl(metrics.netPnl)) across \(NumberDisplay.integer(metrics.knownResultCount)) priced trades. No other pattern cleared the sample minimum."
    }

    private static func whatChanged(metrics: TradingReportMetrics, prior: [Trade]?) -> String? {
        guard let prior else { return nil }
        let priorPriced = prior.compactMap { knownPnl($0) }
        guard metrics.knownResultCount >= comparativeMinimum, priorPriced.count >= comparativeMinimum else {
            return nil
        }
        let priorNet = priorPriced.reduce(0, +)
        let delta = metrics.netPnl - priorNet
        if delta == 0 { return "Net P&L matched the same window in the prior period." }
        let direction = delta > 0 ? "higher" : "lower"
        return "Compared with the same window in the prior period, net P&L was \(formatPnl(abs(delta))) \(direction)."
    }

    private static func ruleAdjustment(_ trades: [Trade], preferences: PreferenceRuleContext?) -> String? {
        guard preferences != nil else { return nil }
        let summary = PreferenceComplianceEngine.evaluate(
            trades.map(PreferenceComplianceEngine.input(from:)),
            context: preferences
        )
        return PreferenceComplianceEngine.primaryAdjustment(for: summary)
    }

    // MARK: - Helpers

    private enum ExtremeMode { case best, worst }

    private static func computeStrategyPnl(_ trades: [Trade]) -> [String: PricedBucket] {
        var map: [String: PricedBucket] = [:]
        for trade in trades {
            let raw = (trade.strategy ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty, let value = knownPnl(trade) else { continue }
            var row = map[raw] ?? PricedBucket()
            row.pnl += value
            row.count += 1
            map[raw] = row
        }
        return map
    }

    private static func computeWeekdayPnl(_ trades: [Trade]) -> [Int: PricedBucket] {
        var map: [Int: PricedBucket] = [:]
        let calendar = TradingReportPeriods.eastern
        for trade in trades {
            let key = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: trade)
            guard !key.isEmpty, let date = dayKeyDate(key), let value = knownPnl(trade) else { continue }
            let day = calendar.component(.weekday, from: date) - 1
            var row = map[day] ?? PricedBucket()
            row.pnl += value
            row.count += 1
            map[day] = row
        }
        return map
    }

    private static func computeHourlyPnl(_ trades: [Trade]) -> [Int: PricedBucket] {
        var map: [Int: PricedBucket] = [:]
        let calendar = TradingReportPeriods.eastern
        for trade in trades {
            guard let value = knownPnl(trade) else { continue }
            let hour = calendar.component(.hour, from: resolveTimeSource(trade))
            var row = map[hour] ?? PricedBucket()
            row.pnl += value
            row.count += 1
            map[hour] = row
        }
        return map
    }

    private static func findBestTrade(_ trades: [Trade]) -> Trade? {
        let best = trades.max {
            (knownPnl($0) ?? -.greatestFiniteMagnitude) < (knownPnl($1) ?? -.greatestFiniteMagnitude)
        }
        guard let best, let pnl = knownPnl(best), pnl > 0 else { return nil }
        return best
    }

    private static func formatHourLabel(_ hour: Int) -> String {
        let period = hour >= 12 ? "PM" : "AM"
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h):00 \(period)"
    }

    private static func formatPnl(_ value: Double) -> String {
        NumberDisplay.reportPnL(value)
    }

    private static func formatRR(_ value: Double) -> String {
        NumberDisplay.decimal(value, minimumFractionDigits: 0, maximumFractionDigits: 2)
    }

    private static func periodNoun(for kind: TradingReportKind) -> String {
        switch kind {
        case .weekly: return "week"
        case .monthly: return "month"
        case .custom: return "period"
        }
    }

    private static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
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
}
