import Foundation

/// Web `lib/tradingReports/generateTradingReport.ts` — deterministic report builder.
///
/// iOS consumes the same rules/copy as web. No separate AI prompts or BFF generate route.
nonisolated enum TradingReportGenerator {
    private static let weekdayLabels = [
        "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
    ]

    private static let sessionLabels: [String: String] = [
        "NY": "New York",
        "London": "London",
        "Asia": "Asia",
    ]

    static func generateAll(
        trades: [Trade],
        now: Date = Date()
    ) -> [TradingReportPeriodKey: TradingReport] {
        var result: [TradingReportPeriodKey: TradingReport] = [:]
        for key in TradingReportPeriodKey.allCases {
            result[key] = generate(trades: trades, periodKey: key, now: now)
        }
        return result
    }

    static func generate(
        trades: [Trade],
        periodKey: TradingReportPeriodKey,
        now: Date = Date()
    ) -> TradingReport {
        let bounds = TradingReportPeriods.bounds(for: periodKey, now: now)
        let periodTrades = filterTrades(trades, bounds: bounds)
        let metrics = buildMetrics(periodTrades)

        let comparisonKey: TradingReportPeriodKey? = {
            switch periodKey {
            case .weeklyThis: return .weeklyLast
            case .monthlyThis: return .monthlyLast
            default: return nil
            }
        }()
        let comparisonTrades = comparisonKey.map {
            filterTrades(trades, bounds: TradingReportPeriods.bounds(for: $0, now: now))
        }

        let strengths = buildStrengths(periodTrades, metrics: metrics, comparisonTrades: comparisonTrades)
        let opportunities = buildOpportunities(periodTrades, metrics: metrics)
        let recommendations = buildRecommendations(
            strengths: strengths,
            opportunities: opportunities,
            metrics: metrics
        )
        let bestTrade = findBestTrade(periodTrades)

        return TradingReport(
            periodKey: periodKey,
            kind: bounds.kind,
            title: bounds.kind.title,
            dateRangeLabel: TradingReportPeriods.dateRangeLabel(
                start: bounds.start,
                end: bounds.end,
                kind: bounds.kind
            ),
            periodStartIso: isoString(bounds.start),
            periodEndIso: isoString(bounds.end),
            generatedAt: now.timeIntervalSince1970 * 1000,
            executiveSummary: buildExecutiveSummary(metrics: metrics, kind: bounds.kind),
            metrics: metrics,
            strengths: strengths,
            opportunities: opportunities,
            recommendations: recommendations,
            bestTradeId: bestTrade.map(\.id.rawValue),
            keyTakeaway: buildKeyTakeaway(
                metrics: metrics,
                strengths: strengths,
                opportunities: opportunities
            ),
            summarySource: "deterministic"
        )
    }

    // MARK: - Filtering

    private static func filterTrades(_ trades: [Trade], bounds: TradingReportPeriods.Bounds) -> [Trade] {
        trades.filter { trade in
            guard let date = resolveTradeDate(trade) else { return false }
            return date >= bounds.start && date <= bounds.end
        }
    }

    /// Web `resolveDashboardTradeDate` — entry → exit → created.
    private static func resolveTradeDate(_ trade: Trade) -> Date? {
        trade.entryAt
    }

    private static func resolveTimeSource(_ trade: Trade) -> Date {
        trade.entryAt
    }

    // MARK: - Metrics

    private static func buildMetrics(_ trades: [Trade]) -> TradingReportMetrics {
        let totalTrades = trades.count
        let wins = trades.filter { pnl($0) > 0 }.count
        let winRate = totalTrades > 0 ? (Double(wins) / Double(totalTrades)) * 100 : 0
        let totalPnL = trades.reduce(0.0) { $0 + pnl($1) }
        let avgRR = averageRr(trades)
        let daily = computeDailyPnl(trades)
        let sessions = computeSessionPnl(trades)
        let bestDay = pickExtremeDay(daily, mode: .best)
        let worstDay = pickExtremeDay(daily, mode: .worst)
        let bestSession = pickExtremeSession(sessions, mode: .best)
        let worstSession = pickExtremeSession(sessions, mode: .worst)

        return TradingReportMetrics(
            netPnl: totalPnL,
            winRate: winRate,
            averageRr: avgRR,
            profitFactor: computeProfitFactor(trades),
            tradesTaken: totalTrades,
            bestDayLabel: bestDay.label,
            bestDayPnl: bestDay.pnl,
            worstDayLabel: worstDay.label,
            worstDayPnl: worstDay.pnl,
            bestSessionLabel: bestSession.label,
            bestSessionPnl: bestSession.pnl,
            worstSessionLabel: worstSession.label,
            worstSessionPnl: worstSession.pnl,
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

    private static func computeDailyPnl(_ trades: [Trade]) -> [String: Double] {
        var map: [String: Double] = [:]
        for trade in trades {
            guard let key = TradingCalendarDay.key(for: trade) else { continue }
            map[key, default: 0] += pnl(trade)
        }
        return map
    }

    private static func pickExtremeDay(
        _ daily: [String: Double],
        mode: ExtremeMode
    ) -> (label: String?, pnl: Double?) {
        guard !daily.isEmpty else { return (nil, nil) }
        let picked: (key: String, pnl: Double)? = {
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

    private static func computeSessionPnl(_ trades: [Trade]) -> [String: Double] {
        var map: [String: Double] = [:]
        for trade in trades {
            guard let bucket = normalizeSessionBucket(trade.sessionLabel) else { continue }
            map[bucket, default: 0] += pnl(trade)
        }
        return map
    }

    private static func pickExtremeSession(
        _ sessions: [String: Double],
        mode: ExtremeMode
    ) -> (label: String?, pnl: Double?) {
        guard !sessions.isEmpty else { return (nil, nil) }
        let picked: (key: String, pnl: Double)? = {
            switch mode {
            case .best: return sessions.max(by: { $0.value < $1.value }).map { ($0.key, $0.value) }
            case .worst: return sessions.min(by: { $0.value < $1.value }).map { ($0.key, $0.value) }
            }
        }()
        guard let picked else { return (nil, nil) }
        return (sessionLabels[picked.key] ?? picked.key, picked.pnl)
    }

    private static func normalizeSessionBucket(_ raw: String?) -> String? {
        let s = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty else { return nil }
        if s == "london" { return "London" }
        if s == "asia" { return "Asia" }
        if s == "ny" || s == "new york" || s == "ny am" || s == "am" || s == "after" {
            return "NY"
        }
        return nil
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
        kind: TradingReportKind
    ) -> String {
        let periodLabel = kind == .weekly ? "week" : "month"
        if metrics.tradesTaken == 0 {
            return "No trades were logged during this \(periodLabel). Log your next session to unlock personalized insights here."
        }

        let tone: String = {
            if metrics.netPnl > 0 { return "positive" }
            if metrics.netPnl < 0 { return "challenging" }
            return "mixed"
        }()

        let execution: String = {
            if metrics.winRate >= 55 { return "solid win rate" }
            if metrics.winRate <= 40 { return "a win rate that needs attention" }
            return "a balanced win rate"
        }()

        let risk: String = {
            if let pf = metrics.profitFactor, pf >= 1.5 { return "healthy profit factor" }
            if let pf = metrics.profitFactor, pf < 1 { return "profit factor below breakeven" }
            return "moderate profit factor"
        }()

        let rr: String = {
            if let average = metrics.averageRr, average >= 1.5 { return "strong average Risk:Reward" }
            if let average = metrics.averageRr, average < 1 { return "below-target Risk:Reward" }
            return "steady Risk:Reward"
        }()

        let tradeWord = metrics.tradesTaken == 1 ? "trade" : "trades"
        return "Overall, you had a \(tone) \(periodLabel) with \(metrics.tradesTaken) \(tradeWord) and \(formatPnl(metrics.netPnl)) net P&L. You posted \(execution) with \(risk) and \(rr)."
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
            strengths.append(
                "You performed best during the \(label) session (\(formatPnl(sessionPnl)))."
            )
        }

        if metrics.winRate >= 55, metrics.tradesTaken >= 3 {
            strengths.append(
                String(
                    format: "Your win rate was %.1f%% across %d trades.",
                    metrics.winRate,
                    metrics.tradesTaken
                )
            )
        }

        if let pf = metrics.profitFactor, pf >= 1.5 {
            strengths.append(
                String(
                    format: "Profit factor reached %.2f, showing winners outweighed losers.",
                    pf
                )
            )
        }

        if let average = metrics.averageRr, average >= 1.2 {
            strengths.append("Average Risk:Reward was \(formatRR(average)).")
        }

        if let comparisonTrades, comparisonTrades.count >= 3,
           let current = metrics.averageRr,
           let prior = averageRr(comparisonTrades),
           current > prior * 1.05 {
            let pct = Int((((current - prior) / prior) * 100).rounded())
            strengths.append("Your average RR improved by \(pct)% versus the prior period.")
        }

        let strategies = computeStrategyPnl(trades)
        if let best = strategies.max(by: { $0.value < $1.value }), best.value > 0 {
            strengths.append("Your top setup was \(best.key) (\(formatPnl(best.value))).")
        }

        if metrics.netPnl > 0, metrics.tradesTaken >= 3 {
            strengths.append("You finished the period net positive.")
        }

        return Array(strengths.prefix(5))
    }

    private static func buildOpportunities(
        _ trades: [Trade],
        metrics: TradingReportMetrics
    ) -> [String] {
        var opportunities: [String] = []

        if let label = metrics.worstSessionLabel,
           let sessionPnl = metrics.worstSessionPnl,
           sessionPnl < 0 {
            opportunities.append(
                "\(label) session trades lost \(formatPnl(abs(sessionPnl)))."
            )
        }

        let hourly = computeHourlyPnl(trades)
        if hourly.count >= 2 {
            let afternoon = hourly.filter { $0.key >= 12 }.reduce(0.0) { $0 + $1.value }
            let morning = hourly.filter { $0.key < 12 }.reduce(0.0) { $0 + $1.value }
            if afternoon < morning, afternoon < 0 {
                opportunities.append("Afternoon trades underperformed relative to the morning.")
            }
        }

        let lossesAfterWins = detectLossesAfterWinStreak(trades)
        if lossesAfterWins >= 2 {
            opportunities.append(
                "\(lossesAfterWins) losing trades followed consecutive winners. Watch for overconfidence."
            )
        }

        let weekdays = computeWeekdayPnl(trades)
        if weekdays.count >= 2,
           let worst = weekdays.min(by: { $0.value < $1.value }),
           worst.value < 0,
           worst.key >= 0,
           worst.key < weekdayLabels.count {
            opportunities.append(
                "\(weekdayLabels[worst.key]) was your weakest weekday (\(formatPnl(worst.value)))."
            )
        }

        if let average = metrics.averageRr, average < 1, metrics.tradesTaken >= 3 {
            opportunities.append(
                "Average Risk:Reward was \(formatRR(average)). Review exits and stop placement."
            )
        }

        if let pf = metrics.profitFactor, pf < 1, metrics.tradesTaken >= 3 {
            opportunities.append(
                String(format: "Profit factor was %.2f. Losses exceeded gains.", pf)
            )
        }

        if hourly.count >= 3,
           let worstHour = hourly.min(by: { $0.value < $1.value }),
           worstHour.value < 0 {
            opportunities.append(
                "Trades around \(formatHourLabel(worstHour.key)) were your weakest hour block."
            )
        }

        return Array(opportunities.prefix(5))
    }

    private static func buildRecommendations(
        strengths: [String],
        opportunities: [String],
        metrics: TradingReportMetrics
    ) -> [String] {
        var recommendations: [String] = []

        if strengths.contains(where: { $0.contains("top setup") }) {
            recommendations.append("Continue focusing on your best-performing setup.")
        }
        if opportunities.contains(where: { $0.lowercased().contains("afternoon") }) {
            recommendations.append("Reduce afternoon trading exposure until performance improves.")
        }
        if opportunities.contains(where: { $0.contains("consecutive winners") }) {
            recommendations.append("Review losing trades taken after extended win streaks.")
        }
        if let pf = metrics.profitFactor, pf >= 1.2 {
            recommendations.append("Maintain your current risk management discipline.")
        } else if metrics.tradesTaken >= 3 {
            recommendations.append("Tighten risk per trade until profit factor recovers above 1.0.")
        }
        if let label = metrics.bestSessionLabel,
           let sessionPnl = metrics.bestSessionPnl,
           sessionPnl > 0 {
            recommendations.append("Prioritize \(label) session setups that are working.")
        }
        recommendations.append("Keep journaling consistently to sharpen future reports.")

        var unique: [String] = []
        for item in recommendations where !unique.contains(item) {
            unique.append(item)
        }
        return Array(unique.prefix(5))
    }

    private static func buildKeyTakeaway(
        metrics: TradingReportMetrics,
        strengths: [String],
        opportunities: [String]
    ) -> String {
        if metrics.tradesTaken == 0 {
            return "Consistent journaling unlocks sharper weekly and monthly intelligence. Log your next trade to start building your report history."
        }
        if let strength = strengths.first, let opportunity = opportunities.first {
            let strengthBody = strength.hasSuffix(".") ? String(strength.dropLast()) : strength
            let opportunityBody = opportunity.prefix(1).lowercased() + opportunity.dropFirst()
            return "\(strengthBody), but \(opportunityBody)"
        }
        if metrics.netPnl > 0 {
            return "Your edge showed up in the data this period. Protect it by doubling down on what worked and trimming the sessions that dragged performance."
        }
        if metrics.netPnl < 0 {
            return "This period highlights where leakage occurred. Use the session and timing breakdowns above to tighten execution next week."
        }
        return "Stay process-focused: the metrics above show where your execution helped and where small adjustments can compound over the next reporting period."
    }

    // MARK: - Helpers

    private enum ExtremeMode { case best, worst }

    private static func computeStrategyPnl(_ trades: [Trade]) -> [String: Double] {
        var map: [String: Double] = [:]
        for trade in trades {
            let raw = (trade.strategy ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }
            map[raw, default: 0] += pnl(trade)
        }
        return map
    }

    private static func computeWeekdayPnl(_ trades: [Trade]) -> [Int: Double] {
        var map: [Int: Double] = [:]
        let calendar = Calendar.current
        for trade in trades {
            guard let date = resolveTradeDate(trade) else { continue }
            let day = calendar.component(.weekday, from: date) - 1 // 0 = Sunday
            map[day, default: 0] += pnl(trade)
        }
        return map
    }

    private static func computeHourlyPnl(_ trades: [Trade]) -> [Int: Double] {
        var map: [Int: Double] = [:]
        let calendar = Calendar.current
        for trade in trades {
            let hour = calendar.component(.hour, from: resolveTimeSource(trade))
            map[hour, default: 0] += pnl(trade)
        }
        return map
    }

    private static func detectLossesAfterWinStreak(_ trades: [Trade]) -> Int {
        let sorted = trades.sorted {
            (resolveTradeDate($0)?.timeIntervalSince1970 ?? 0)
                < (resolveTradeDate($1)?.timeIntervalSince1970 ?? 0)
        }
        var winStreak = 0
        var lossAfterStreak = 0
        for trade in sorted {
            let value = pnl(trade)
            if value > 0 {
                winStreak += 1
                continue
            }
            if value < 0, winStreak >= 2 {
                lossAfterStreak += 1
            }
            winStreak = 0
        }
        return lossAfterStreak
    }

    private static func findBestTrade(_ trades: [Trade]) -> Trade? {
        trades.max(by: { pnl($0) < pnl($1) })
    }

    private static func formatHourLabel(_ hour: Int) -> String {
        let period = hour >= 12 ? "PM" : "AM"
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h):00 \(period)"
    }

    private static func formatPnl(_ value: Double) -> String {
        let absValue = abs(value)
        let formatted = absValue.formatted(
            .number.precision(.fractionLength(2)).grouping(.automatic)
        )
        return value < 0 ? "-$\(formatted)" : "$\(formatted)"
    }

    private static func formatRR(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
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
}
