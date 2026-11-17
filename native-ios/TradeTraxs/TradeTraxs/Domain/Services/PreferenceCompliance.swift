import Foundation

/// Historical personal-rule checks. Mirrors `lib/analytics/preferenceCompliance.ts`.
/// A blank preference is not a rule. Missing P&L stays out of averages.
nonisolated struct PreferenceRuleContext: Sendable, Equatable {
    var revisions: [TradingPreferenceRevision]
    var global: TradingPreferenceGlobal?
    var overrides: [TradingPreferenceAccountOverride]
}

nonisolated struct PsychologyRuleSnapshot: Sendable, Equatable {
    var consecutiveLossPause: Int?
    var maxTradesPerDay: Int?
    var waitAfterLossMinutes: Int?

    static let none = PsychologyRuleSnapshot(
        consecutiveLossPause: nil,
        maxTradesPerDay: nil,
        waitAfterLossMinutes: nil
    )
}

nonisolated struct PreferenceCompliance: Sendable, Equatable {
    struct Side: Sendable, Equatable {
        var trades = 0
        var priced = 0
        var net = 0.0

        mutating func add(_ pnl: Double?) {
            trades += 1
            guard let pnl else { return }
            priced += 1
            net += pnl
        }

        var average: Double? { priced > 0 ? net / Double(priced) : nil }
    }

    var usesHistory = false
    var sessionActive = false
    var inSession = Side()
    var outsideSession = Side()
    var instrumentsActive = false
    var inInstruments = Side()
    var outsideInstruments = Side()
    var hoursActive = false
    var inHours = Side()
    var outsideHours = Side()
    var rulesActive = false
    var ruleFamilies = 0
    var insideRules = Side()
    var outsideRules = Side()
    var capActive = false
    var overCapDays = 0
    var overCap = Side()
    var withinCap = Side()
    var lossLimitActive = false
    var lossLimitDays = 0
    var afterBreach = Side()
    var targetPaired = 0
    var uniformTargetRr: Double?
    var avgMaxRr: Double?
    var shortOfTarget = 0
    var minRrActive = false
    var belowMinRr = Side()
    var withinMinRr = Side()
    var minRrPaired = 0
    var allowedDaysActive = false
    var outsideAllowedDays = Side()
    var withinAllowedDays = Side()
    var maxContractsActive = false
    var overMaxContracts = Side()
    var withinMaxContracts = Side()
    var maxRiskActive = false
    var maxRiskPaired = 0
    var overMaxRisk = Side()
    var withinMaxRisk = Side()
    var weeklyLossActive = false
    var weeklyLossScopeLabel: String?
    var weeklyLossWeeks = 0
    var afterWeeklyLossBreach = Side()
    var profitStopActive = false
    var profitStopScopeLabel: String?
    var afterProfitTarget = Side()
    var capScopeLabel: String?
    var lossLimitScopeLabel: String?
}

nonisolated enum PreferenceComplianceEngine {
    static let comparativeMinimum = 5

    struct Input: Sendable {
        var tradeID: String?
        var at: Date
        var accountID: String?
        var session: String?
        var symbol: String?
        var pnl: Double?
        var easternMinute: Int
        var dayKey: String
        var weekKey: String?
        var weekday: TradingRuleWeekday?
        var maxRr: Double?
        var plannedRr: Double?
        var contracts: Int?
        var dollarRisk: Double?
    }

    /// Latest saved preferences from live global + account override (not time-travelled).
    static func configuredRulesNow(
        in context: PreferenceRuleContext?,
        accountID: String? = nil
    ) -> ResolvedTradingPreferences {
        guard let context else { return .empty }
        return currentConfiguredRules(in: context, accountID: accountID)
    }

    /// Earliest global revision timestamp — start of recorded rule history.
    static func firstGlobalRuleEffectiveAt(in context: PreferenceRuleContext?) -> Date? {
        guard let context else { return nil }
        return context.revisions
            .filter { $0.accountID == nil }
            .map(\.effectiveFrom)
            .min()
    }

    static func rules(
        in context: PreferenceRuleContext?,
        at: Date,
        accountID: String?
    ) -> ResolvedTradingPreferences {
        guard let context else { return .empty }
        guard !context.revisions.isEmpty else {
            // Without revision history we do not apply live globals to past trades.
            return .empty
        }

        let historical = TradingPreferenceRules.activeAt(
            context.revisions,
            at: at,
            accountID: accountID.flatMap { TradingAccountID($0) }
        )

        if let firstGlobal = firstGlobalRuleEffectiveAt(in: context), at < firstGlobal {
            if applyRulesToPastTradesEnabled(in: context) {
                let current = currentConfiguredRules(in: context, accountID: accountID)
                if current.hasActiveRuleChecks {
                    return current
                }
            }
            return historical
        }

        return historical
    }

    static func applyRulesToPastTradesEnabled(in context: PreferenceRuleContext?) -> Bool {
        context?.global?.applyRulesToPastTrades ?? false
    }

    static func usesRetrospectiveRuleApplication(
        in context: PreferenceRuleContext?,
        at: Date,
        accountID: String?
    ) -> Bool {
        guard applyRulesToPastTradesEnabled(in: context), let context, !context.revisions.isEmpty else {
            return false
        }
        guard let firstGlobal = firstGlobalRuleEffectiveAt(in: context), at < firstGlobal else {
            return false
        }
        return currentConfiguredRules(in: context, accountID: accountID).hasActiveRuleChecks
    }

    private static func currentConfiguredRules(
        in context: PreferenceRuleContext,
        accountID: String?
    ) -> ResolvedTradingPreferences {
        guard let global = context.global else { return .empty }
        let override = context.overrides.first { $0.accountID.rawValue == accountID }
        return TradingPreferenceRules.resolve(global: global, account: override)
    }

    static func psychologyRules(
        in context: PreferenceRuleContext?,
        at: Date
    ) -> PsychologyRuleSnapshot {
        let resolved = rules(in: context, at: at, accountID: nil)
        return PsychologyRuleSnapshot(
            consecutiveLossPause: resolved.consecutiveLossPause,
            maxTradesPerDay: resolved.maxTradesPerDay,
            waitAfterLossMinutes: resolved.waitAfterLossMinutes
        )
    }

    static func currentPsychologyRules(in context: PreferenceRuleContext?) -> PsychologyRuleSnapshot {
        guard let context else { return .none }
        if let latest = context.revisions.max(by: { $0.effectiveFrom < $1.effectiveFrom }) {
            return psychologyRules(in: context, at: latest.effectiveFrom)
        }
        return PsychologyRuleSnapshot(
            consecutiveLossPause: context.global?.consecutiveLossPause,
            maxTradesPerDay: context.global?.maxTradesPerDay,
            waitAfterLossMinutes: context.global?.waitAfterLossMinutes
        )
    }

    static func input(from trade: Trade) -> Input {
        let pnl = trade.realizedPnL.map { NSDecimalNumber(decimal: $0.amount).doubleValue }
        let maxRr = trade.maxRrReached.map { NSDecimalNumber(decimal: $0).doubleValue }
        let plannedRrRaw = trade.riskReward.map { NSDecimalNumber(decimal: $0).doubleValue }
        let plannedRr = plannedRrRaw.flatMap { $0 > 0 ? $0 : nil }
        let quantity = NSDecimalNumber(decimal: trade.quantity).doubleValue
        let contracts: Int? = {
            guard quantity > 0, quantity == quantity.rounded(), quantity <= 10_000 else { return nil }
            return Int(quantity)
        }()
        let dollarRiskRaw = trade.dollarRisk.map { NSDecimalNumber(decimal: $0).doubleValue }
        let dollarRisk = dollarRiskRaw.flatMap { $0 > 0 ? $0 : nil }
        let symbol = trade.symbol.ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let dayKey = TradingSessionLabel.easternTradeDateString(from: trade.entryAt)
        return Input(
            tradeID: trade.id.rawValue,
            at: trade.entryAt,
            accountID: trade.accountID?.rawValue,
            session: TradingSessionLabel.canonicalLabel(fromStored: trade.sessionLabel),
            symbol: symbol.isEmpty ? nil : symbol,
            pnl: pnl,
            easternMinute: TradingSessionLabel.easternMinutesSinceMidnight(on: trade.entryAt),
            dayKey: dayKey,
            weekKey: TradingRuleScopeMath.easternWeekKey(from: trade.entryAt),
            weekday: TradingRuleScopeMath.easternWeekday(from: trade.entryAt),
            maxRr: maxRr,
            plannedRr: plannedRr,
            contracts: contracts,
            dollarRisk: dollarRisk
        )
    }

    static func evaluate(
        _ inputs: [Input],
        context: PreferenceRuleContext?
    ) -> PreferenceCompliance {
        var summary = PreferenceCompliance()
        summary.usesHistory = !(context?.revisions.isEmpty ?? true)
        guard context != nil else { return summary }

        let ordered = inputs.sorted { $0.at < $1.at }
        var byCapDayBucket: [String: [Input]] = [:]
        var byLossDayBucket: [String: [Input]] = [:]
        var byProfitDayBucket: [String: [Input]] = [:]
        var byWeekBucket: [String: [Input]] = [:]
        var targets = Set<Double>()
        var maxSum = 0.0

        for trade in ordered {
            let resolved = rules(in: context, at: trade.at, accountID: trade.accountID)
            var families = 0
            var violated = false

            if !resolved.preferredSessions.isEmpty, let session = trade.session {
                summary.sessionActive = true
                let inside = resolved.preferredSessions.contains(session)
                if inside { summary.inSession.add(trade.pnl) } else { summary.outsideSession.add(trade.pnl) }
                families += 1
                if !inside { violated = true }
            }
            if !resolved.primaryInstruments.isEmpty, let symbol = trade.symbol {
                summary.instrumentsActive = true
                let inside = resolved.primaryInstruments.contains(symbol)
                if inside { summary.inInstruments.add(trade.pnl) } else { summary.outsideInstruments.add(trade.pnl) }
                families += 1
                if !inside { violated = true }
            }
            if let hours = resolved.plannedHours {
                summary.hoursActive = true
                let inside = minuteInWindow(trade.easternMinute, start: hours.startMinute, end: hours.endMinute)
                if inside { summary.inHours.add(trade.pnl) } else { summary.outsideHours.add(trade.pnl) }
                families += 1
                if !inside { violated = true }
            }
            if families > 0 {
                summary.rulesActive = true
                if violated { summary.outsideRules.add(trade.pnl) } else { summary.insideRules.add(trade.pnl) }
            }

            if let target = resolved.targetRr, let maxRr = trade.maxRr {
                summary.targetPaired += 1
                maxSum += maxRr
                targets.insert(target)
                if maxRr < target { summary.shortOfTarget += 1 }
            }

            if let minRr = resolved.minAcceptableRr {
                summary.minRrActive = true
                if let planned = trade.plannedRr {
                    summary.minRrPaired += 1
                    if planned < minRr {
                        summary.belowMinRr.add(trade.pnl)
                    } else {
                        summary.withinMinRr.add(trade.pnl)
                    }
                }
            }

            if !resolved.allowedTradingDays.isEmpty, let weekday = trade.weekday {
                summary.allowedDaysActive = true
                let inside = resolved.allowedTradingDays.contains(weekday)
                if inside { summary.withinAllowedDays.add(trade.pnl) } else { summary.outsideAllowedDays.add(trade.pnl) }
            }

            if let cap = resolved.maxContractsPerTrade {
                summary.maxContractsActive = true
                if let contracts = trade.contracts {
                    if contracts > cap {
                        summary.overMaxContracts.add(trade.pnl)
                    } else {
                        summary.withinMaxContracts.add(trade.pnl)
                    }
                }
            }

            if resolved.maxRiskPerTrade != nil {
                summary.maxRiskActive = true
                if let risk = trade.dollarRisk {
                    summary.maxRiskPaired += 1
                    if risk > resolved.maxRiskPerTrade! {
                        summary.overMaxRisk.add(trade.pnl)
                    } else {
                        summary.withinMaxRisk.add(trade.pnl)
                    }
                }
            }

            if let weekKey = trade.weekKey {
                let rulesAtTrade = rules(in: context, at: trade.at, accountID: trade.accountID)
                let weekBucket = TradingRuleScopeMath.scopedWeekBucket(
                    weekKey: weekKey,
                    accountID: trade.accountID,
                    scope: rulesAtTrade.maxWeeklyLossScope
                )
                byWeekBucket[weekBucket, default: []].append(trade)
            }

            let capRules = rules(in: context, at: trade.at, accountID: trade.accountID)
            if summary.capScopeLabel == nil {
                summary.capScopeLabel = TradingRuleScopeMath.scopeBucketLabel(capRules.maxTradesPerDayScope)
            }
            if summary.lossLimitScopeLabel == nil {
                summary.lossLimitScopeLabel = TradingRuleScopeMath.scopeBucketLabel(capRules.dailyLossLimitScope)
            }
            if summary.profitStopScopeLabel == nil {
                summary.profitStopScopeLabel = TradingRuleScopeMath.scopeBucketLabel(capRules.dailyProfitRulesScope)
            }
            if summary.weeklyLossScopeLabel == nil {
                summary.weeklyLossScopeLabel = TradingRuleScopeMath.scopeBucketLabel(capRules.maxWeeklyLossScope)
            }

            let capKey = TradingRuleScopeMath.scopedDayBucket(
                dayKey: trade.dayKey,
                accountID: trade.accountID,
                scope: capRules.maxTradesPerDayScope
            )
            byCapDayBucket[capKey, default: []].append(trade)

            let lossKey = TradingRuleScopeMath.scopedDayBucket(
                dayKey: trade.dayKey,
                accountID: trade.accountID,
                scope: capRules.dailyLossLimitScope
            )
            byLossDayBucket[lossKey, default: []].append(trade)

            let profitKey = TradingRuleScopeMath.scopedDayBucket(
                dayKey: trade.dayKey,
                accountID: trade.accountID,
                scope: capRules.dailyProfitRulesScope
            )
            byProfitDayBucket[profitKey, default: []].append(trade)
        }

        summary.ruleFamilies =
            (summary.sessionActive ? 1 : 0) +
            (summary.instrumentsActive ? 1 : 0) +
            (summary.hoursActive ? 1 : 0)
        if summary.targetPaired > 0 {
            summary.avgMaxRr = maxSum / Double(summary.targetPaired)
            summary.uniformTargetRr = targets.count == 1 ? targets.first : nil
        }

        for day in byCapDayBucket.values {
            let sortedDay = day.sorted { $0.at < $1.at }
            var index = 0
            var dayOverCap = false
            for trade in sortedDay {
                index += 1
                let resolved = rules(in: context, at: trade.at, accountID: trade.accountID)
                guard let cap = resolved.maxTradesPerDay else { continue }
                summary.capActive = true
                let over = index > cap
                if over {
                    summary.overCap.add(trade.pnl)
                    dayOverCap = true
                } else {
                    summary.withinCap.add(trade.pnl)
                }
            }
            if dayOverCap { summary.overCapDays += 1 }
        }

        for day in byLossDayBucket.values {
            let sortedDay = day.sorted { $0.at < $1.at }
            var running = 0.0
            var breached = false
            for trade in sortedDay {
                let resolved = rules(in: context, at: trade.at, accountID: trade.accountID)
                guard resolved.dailyLossLimit != nil else { continue }
                summary.lossLimitActive = true
                if let pnl = trade.pnl { running += pnl }
                if !breached, let limit = resolved.dailyLossLimit, running <= -limit {
                    breached = true
                    continue
                }
                if breached { summary.afterBreach.add(trade.pnl) }
            }
            if breached { summary.lossLimitDays += 1 }
        }

        for day in byProfitDayBucket.values {
            let sortedDay = day.sorted { $0.at < $1.at }
            var running = 0.0
            var profitThresholdReached = false
            for trade in sortedDay {
                let resolved = rules(in: context, at: trade.at, accountID: trade.accountID)
                guard resolved.stopAfterDailyProfitTarget, resolved.dailyProfitTarget != nil else { continue }
                summary.profitStopActive = true
                if profitThresholdReached {
                    summary.afterProfitTarget.add(trade.pnl)
                }
                if let pnl = trade.pnl { running += pnl }
                if !profitThresholdReached,
                   let target = resolved.dailyProfitTarget,
                   running >= target {
                    profitThresholdReached = true
                }
            }
        }

        for week in byWeekBucket.values {
            let sortedWeek = week.sorted { $0.at < $1.at }
            var running = 0.0
            var breached = false
            for trade in sortedWeek {
                let resolved = rules(in: context, at: trade.at, accountID: trade.accountID)
                guard resolved.maxWeeklyLoss != nil else { continue }
                summary.weeklyLossActive = true
                if breached {
                    summary.afterWeeklyLossBreach.add(trade.pnl)
                    continue
                }
                if let pnl = trade.pnl { running += pnl }
                if let limit = resolved.maxWeeklyLoss, running <= -limit {
                    breached = true
                    summary.weeklyLossWeeks += 1
                }
            }
        }

        return summary
    }

    static func lines(for summary: PreferenceCompliance) -> [String] {
        var lines: [String] = []
        let sessionTotal = summary.inSession.trades + summary.outsideSession.trades
        if summary.sessionActive, summary.outsideSession.trades > 0 {
            lines.append("\(summary.outsideSession.trades) of \(sessionTotal) trades were outside your preferred sessions.")
        }
        let instrumentTotal = summary.inInstruments.trades + summary.outsideInstruments.trades
        if summary.instrumentsActive, summary.outsideInstruments.trades > 0 {
            lines.append("\(summary.outsideInstruments.trades) of \(instrumentTotal) trades were outside your primary instruments.")
        }
        let hourTotal = summary.inHours.trades + summary.outsideHours.trades
        if summary.hoursActive, summary.outsideHours.trades > 0 {
            lines.append("\(summary.outsideHours.trades) of \(hourTotal) trades were outside your planned trading hours.")
        }
        if summary.capActive, summary.overCap.trades > 0 {
            let trades = summary.overCap.trades == 1 ? "1 trade was" : "\(summary.overCap.trades) trades were"
            let days = summary.overCapDays == 1 ? "1 day" : "\(summary.overCapDays) days"
            let scope = summary.capScopeLabel.map { " (\($0))" } ?? ""
            lines.append("\(trades) beyond your daily trade cap\(scope), across \(days).")
        }
        if summary.lossLimitActive, summary.lossLimitDays > 0 {
            let scope = summary.lossLimitScopeLabel.map { " (\($0))" } ?? ""
            lines.append(summary.lossLimitDays == 1
                ? "1 day crossed your daily loss limit\(scope)."
                : "\(summary.lossLimitDays) days crossed your daily loss limit\(scope).")
        }
        if summary.profitStopActive, summary.afterProfitTarget.trades > 0 {
            let scope = summary.profitStopScopeLabel.map { " (\($0))" } ?? ""
            let trades = summary.afterProfitTarget.trades == 1
                ? "1 trade was"
                : "\(summary.afterProfitTarget.trades) trades were"
            lines.append(
                "\(trades) taken after your daily profit target was reached\(scope), not including the trade that first hit the target."
            )
        }
        if summary.weeklyLossActive, summary.weeklyLossWeeks > 0 {
            let scope = summary.weeklyLossScopeLabel.map { " (\($0))" } ?? ""
            lines.append(summary.weeklyLossWeeks == 1
                ? "1 Eastern week crossed your weekly loss limit\(scope)."
                : "\(summary.weeklyLossWeeks) Eastern weeks crossed your weekly loss limit\(scope).")
        }
        if summary.allowedDaysActive, summary.outsideAllowedDays.trades > 0 {
            let total = summary.outsideAllowedDays.trades + summary.withinAllowedDays.trades
            lines.append(
                "\(summary.outsideAllowedDays.trades) of \(total) trades fell on days outside your allowed trading days."
            )
        }
        if summary.maxContractsActive, summary.overMaxContracts.trades > 0 {
            let trades = summary.overMaxContracts.trades == 1
                ? "1 trade exceeded"
                : "\(summary.overMaxContracts.trades) trades exceeded"
            lines.append("\(trades) your maximum contracts-per-trade limit (trades with a recorded contract size).")
        }
        if summary.minRrActive, summary.minRrPaired > 0, summary.belowMinRr.trades > 0 {
            lines.append(
                "\(summary.belowMinRr.trades) of \(summary.minRrPaired) trades with a planned R:R were below your minimum acceptable R:R."
            )
        }
        if summary.maxRiskActive {
            if summary.maxRiskPaired == 0 {
                lines.append(
                    "Maximum risk per trade is set, but none of your trades in this period recorded dollar risk at entry."
                )
            } else if summary.overMaxRisk.trades > 0 {
                let trades = summary.overMaxRisk.trades == 1
                    ? "1 trade exceeded"
                    : "\(summary.overMaxRisk.trades) trades exceeded"
                lines.append(
                    "\(trades) your maximum risk per trade among \(summary.maxRiskPaired) trades with recorded dollar risk."
                )
            }
        }

        if summary.ruleFamilies >= 2 {
            if let combined = compareLine(
                "Trades inside your personal rules",
                summary.insideRules,
                "Trades outside them",
                summary.outsideRules
            ) {
                lines.append(combined)
            }
        } else {
            if let session = compareLine("Inside your preferred sessions", summary.inSession, "Outside those sessions", summary.outsideSession) {
                lines.append(session)
            }
            if let instruments = compareLine("Trades in your primary instruments", summary.inInstruments, "Outside those instruments", summary.outsideInstruments) {
                lines.append(instruments)
            }
            if let hours = compareLine("Trades inside your planned hours", summary.inHours, "Outside those hours", summary.outsideHours) {
                lines.append(hours)
            }
        }
        if let cap = compareLine("Trades within your daily cap", summary.withinCap, "Trades beyond it", summary.overCap) {
            lines.append(cap)
        }
        if summary.afterBreach.priced >= comparativeMinimum, let after = summary.afterBreach.average {
            lines.append("After the daily loss limit was crossed, the next priced trades averaged \(money(after)) (\(summary.afterBreach.priced) trades).")
        }
        if let target = summary.uniformTargetRr,
           let maxRr = summary.avgMaxRr,
           summary.targetPaired >= comparativeMinimum {
            let maxLabel = formatR(maxRr)
            let targetLabel = formatR(target)
            lines.append(maxRr < target
                ? "Average max R was \(maxLabel), short of your \(targetLabel)R target, across \(summary.targetPaired) trades."
                : "Average max R was \(maxLabel) versus your \(targetLabel)R target, across \(summary.targetPaired) trades.")
        }
        return lines
    }

    static func primaryAdjustment(for summary: PreferenceCompliance) -> String? {
        if summary.ruleFamilies >= 2, worse(summary.insideRules, summary.outsideRules) {
            return compareLine("Trades inside your personal rules", summary.insideRules, "Trades outside them", summary.outsideRules)
        }
        if worse(summary.inSession, summary.outsideSession) {
            return compareLine("Inside your preferred sessions", summary.inSession, "Outside those sessions", summary.outsideSession)
        }
        if worse(summary.inHours, summary.outsideHours) {
            return compareLine("Trades inside your planned hours", summary.inHours, "Outside those hours", summary.outsideHours)
        }
        if worse(summary.inInstruments, summary.outsideInstruments) {
            return compareLine("Trades in your primary instruments", summary.inInstruments, "Outside those instruments", summary.outsideInstruments)
        }
        if worse(summary.withinCap, summary.overCap) {
            return compareLine("Trades within your daily cap", summary.withinCap, "Trades beyond it", summary.overCap)
        }
        if summary.afterBreach.priced >= comparativeMinimum, let after = summary.afterBreach.average {
            return "After the daily loss limit was crossed, the next priced trades averaged \(money(after)) (\(summary.afterBreach.priced) trades)."
        }
        if let target = summary.uniformTargetRr,
           let maxRr = summary.avgMaxRr,
           maxRr < target,
           summary.targetPaired >= comparativeMinimum {
            return "Average max R was \(formatR(maxRr)), short of your \(formatR(target))R target, across \(summary.targetPaired) trades."
        }
        return nil
    }

    static func fingerprint(_ context: PreferenceRuleContext?) -> String {
        guard let context else { return "noprefs" }
        let latest = context.revisions.max(by: { $0.effectiveFrom < $1.effectiveFrom })?.effectiveFrom.timeIntervalSince1970 ?? 0
        let applyPast = context.global?.applyRulesToPastTrades == true ? 1 : 0
        let goal = context.global?.personalComplianceTargetPercent.map { String(format: "%.2f", $0) } ?? "goal:nil"
        return "\(context.revisions.count):\(latest):\(context.global?.updatedAt?.timeIntervalSince1970 ?? 0):\(context.overrides.count):\(applyPast):\(goal)"
    }

    private static func bothSides(_ left: PreferenceCompliance.Side, _ right: PreferenceCompliance.Side) -> Bool {
        left.priced >= comparativeMinimum && right.priced >= comparativeMinimum
    }

    private static func worse(_ left: PreferenceCompliance.Side, _ right: PreferenceCompliance.Side) -> Bool {
        guard bothSides(left, right), let a = left.average, let b = right.average else { return false }
        return b < a
    }

    private static func compareLine(
        _ insideLabel: String,
        _ inside: PreferenceCompliance.Side,
        _ outsideLabel: String,
        _ outside: PreferenceCompliance.Side
    ) -> String? {
        guard bothSides(inside, outside), let insideAvg = inside.average, let outsideAvg = outside.average else {
            return nil
        }
        return "\(insideLabel) averaged \(money(insideAvg)) (\(inside.priced) priced). \(outsideLabel) averaged \(money(outsideAvg)) (\(outside.priced) priced)."
    }

    private static func minuteInWindow(_ minute: Int, start: Int, end: Int) -> Bool {
        if end > start { return minute >= start && minute < end }
        return minute >= start || minute < end
    }

    private static func money(_ value: Double) -> String {
        let formatted = NumberDisplay.currency(abs(value), minimumFractionDigits: 2, maximumFractionDigits: 2)
        return value < 0 ? "-\(formatted)" : formatted
    }

    static func formatR(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.1f", rounded)
    }
}
