import Foundation

/// Mirrors `lib/analytics/tradingRulesComplianceAnalytics.ts`.
nonisolated enum TradingRulesComplianceAnalytics {
    enum Outcome: String, Sendable, Hashable, Codable {
        case followed
        case violated
        case unevaluated
        case notApplicable

        /// Included in adherence % numerator/denominator (followed ÷ (followed + violated)).
        var countsInAdherenceScore: Bool {
            switch self {
            case .followed, .violated: return true
            case .unevaluated, .notApplicable: return false
            }
        }
    }

    enum Level: String, Sendable, Hashable {
        case trade
        case day
        case week
    }

    enum RuleID: String, Sendable, Hashable, CaseIterable {
        case preferredSession = "preferred_session"
        case primaryInstrument = "primary_instrument"
        case plannedHours = "planned_hours"
        case allowedTradingDay = "allowed_trading_day"
        case minPlannedRr = "min_planned_rr"
        case maxContracts = "max_contracts"
        case maxRiskPerTrade = "max_risk_per_trade"
        case targetRrMax = "target_rr_max"
        case maxTradesPerDay = "max_trades_per_day"
        case dailyLossLimit = "daily_loss_limit"
        case dailyProfitStop = "daily_profit_stop"
        case weeklyLossLimit = "weekly_loss_limit"
        case consecutiveLossPause = "consecutive_loss_pause"
        case waitAfterLoss = "wait_after_loss"

        var label: String {
            switch self {
            case .preferredSession: return "Preferred session"
            case .primaryInstrument: return "Primary instrument"
            case .plannedHours: return "Planned trading hours"
            case .allowedTradingDay: return "Allowed trading day"
            case .minPlannedRr: return "Min Planned R:R"
            case .maxContracts: return "Max Contracts / Trade"
            case .maxRiskPerTrade: return "Max Risk / Trade"
            case .targetRrMax: return "Target R:R (max reached)"
            case .maxTradesPerDay: return "Max Trades / Day"
            case .dailyLossLimit: return "Daily loss limit"
            case .dailyProfitStop: return "Daily profit stop"
            case .weeklyLossLimit: return "Weekly loss limit"
            case .consecutiveLossPause: return "Consecutive loss pause"
            case .waitAfterLoss: return "Wait after loss"
            }
        }
    }

    struct Check: Identifiable, Sendable, Hashable {
        var id: String
        var ruleID: RuleID
        var outcome: Outcome
        var level: Level
        var at: Date
        var dayKey: String
        var weekKey: String?
        var monthKey: String
        var tradeID: String?
        var accountID: String?
        var scopeLabel: String?
        var detail: String
        var pnl: Double?
    }

    struct ViolationEvent: Identifiable, Sendable {
        var id: String
        var at: Date
        var dayKey: String
        var tradeID: String?
        var accountID: String?
        var ruleID: RuleID
        var ruleLabel: String
        var level: Level
        var scopeLabel: String?
        var summary: String
    }

    struct ImpactSide: Sendable {
        var priced = 0
        var wins = 0
        var losses = 0
        var breakeven = 0
        var totalNetPnl = 0.0
        var grossWins = 0.0
        var grossLosses = 0.0
        var realizedRrSum = 0.0
        var realizedRrCount = 0
        var tradeSamples: [TradingRulesRuleImpact.TradeSample] = []
        var avgNetPnl: Double?
        var winRateFraction: Double?
        var profitFactor: Double?
        var expectancy: Double?
        var avgRealizedRr: Double?

        /// Legacy field used by older UI paths, same as `totalNetPnl`.
        var totalPnl: Double { totalNetPnl }
    }

    struct ImpactRow: Identifiable, Sendable {
        var id: String { ruleID.rawValue }
        var ruleID: RuleID
        var ruleLabel: String
        var followed: ImpactSide
        var violated: ImpactSide
        var sufficientSample: Bool
        var summary: String?
        var avgPnlDelta: Double?
        var winRateDeltaPoints: Double?
    }

    struct Score: Sendable {
        var adherencePercent: Double?
        var followed: Int
        var violated: Int
        var unevaluated: Int
        var evaluated: Int
        var explanation: String
    }

    struct TrendPoint: Identifiable, Sendable {
        var id: String { key }
        var key: String
        var label: String
        var adherencePercent: Double?
        var evaluated: Int
        var followed: Int
        var violations: Int
        var unevaluatedChecks: Int
        var tradeCount: Int
        var insufficientData: Bool
        var coverageNote: String?
    }

    struct Result: Sendable {
        var score: Score
        var impacts: [ImpactRow]
        var violations: [ViolationEvent]
        var weeklyTrend: [TrendPoint]
        var monthlyTrend: [TrendPoint]
        var usesHistoricalRevisions: Bool
        /// Trades scored with current rules because they predate the first saved revision.
        var retrospectivelyEvaluatedTrades: Int
        var violationPatterns: TradingRulesViolationPatterns.Bundle
        /// Internal, used for day drill-down without re-running the engine.
        var complianceChecks: [Check]
        var impactHighlights: [TradingRulesRuleImpact.ComparisonHighlight]
        var disciplineProgress: TradingRulesDisciplineProgress.Bundle
    }

    private struct ScopedBuckets: Sendable {
        var capDay: [String: [PreferenceComplianceEngine.Input]] = [:]
        var lossDay: [String: [PreferenceComplianceEngine.Input]] = [:]
        var profitDay: [String: [PreferenceComplianceEngine.Input]] = [:]
        var week: [String: [PreferenceComplianceEngine.Input]] = [:]
    }

    struct BuildState {
        var checks: [Check] = []
        var nextCheckID = 0

        mutating func pushCheck(
            rule: RuleID,
            outcome: Outcome,
            level: Level,
            input: PreferenceComplianceEngine.Input,
            scope: String?,
            detail: String
        ) {
            nextCheckID += 1
            let check = Check(
                id: "chk-\(nextCheckID)",
                ruleID: rule,
                outcome: outcome,
                level: level,
                at: input.at,
                dayKey: input.dayKey,
                weekKey: input.weekKey,
                monthKey: monthKey(input.dayKey),
                tradeID: input.tradeID,
                accountID: input.accountID,
                scopeLabel: scope,
                detail: detail,
                pnl: input.pnl
            )
            checks.append(check)
        }

        mutating func recordTrade(
            rule: RuleID,
            input: PreferenceComplianceEngine.Input,
            outcome: Outcome,
            level: Level,
            scope: String?,
            detail: String
        ) {
            pushCheck(
                rule: rule,
                outcome: outcome,
                level: level,
                input: input,
                scope: scope,
                detail: detail
            )
        }
    }

    private static func minuteInWindow(_ minute: Int, start: Int, end: Int) -> Bool {
        if end > start { return minute >= start && minute < end }
        return minute >= start || minute < end
    }

    private static func monthKey(_ dayKey: String) -> String {
        dayKey.count >= 7 ? String(dayKey.prefix(7)) : dayKey
    }

    private static func formatMoney(_ value: Double) -> String {
        let abs = abs(value)
        let text = String(format: "%.2f", abs)
        return value < 0 ? "-$\(text)" : "$\(text)"
    }

    private static func optionalIntString(_ value: Int?) -> String {
        guard let value else { return "" }
        return String(value)
    }

    private static func optionalDoubleString(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(value)
    }

    private static func rulesFingerprint(_ rules: ResolvedTradingPreferences) -> String {
        let hoursStart: String
        let hoursEnd: String
        if let hours = rules.plannedHours {
            hoursStart = String(hours.startMinute)
            hoursEnd = String(hours.endMinute)
        } else {
            hoursStart = ""
            hoursEnd = ""
        }

        var parts: [String] = []
        parts.reserveCapacity(18)
        parts.append(rules.preferredSessions.joined(separator: ","))
        parts.append(rules.primaryInstruments.joined(separator: ","))
        parts.append(hoursStart)
        parts.append(hoursEnd)
        parts.append(optionalIntString(rules.maxTradesPerDay))
        parts.append(optionalDoubleString(rules.dailyLossLimit))
        parts.append(optionalDoubleString(rules.dailyProfitTarget))
        parts.append(rules.stopAfterDailyProfitTarget ? "1" : "0")
        parts.append(optionalDoubleString(rules.maxWeeklyLoss))
        parts.append(optionalDoubleString(rules.minAcceptableRr))
        parts.append(optionalIntString(rules.maxContractsPerTrade))
        parts.append(optionalDoubleString(rules.maxRiskPerTrade))
        parts.append(optionalDoubleString(rules.targetRr))
        parts.append(rules.allowedTradingDays.map(\.rawValue).joined(separator: ","))
        parts.append(rules.maxTradesPerDayScope.rawValue)
        parts.append(rules.dailyLossLimitScope.rawValue)
        parts.append(rules.dailyProfitRulesScope.rawValue)
        parts.append(rules.maxWeeklyLossScope.rawValue)
        return parts.joined(separator: "|")
    }

    private static func buildTrend(
        checks: [Check],
        keyFn: (Check) -> String,
        inputKeyFn: (PreferenceComplianceEngine.Input) -> String,
        labelFn: (String) -> String,
        rulesCache: TradingRulesResolvedRulesCache,
        ordered: [PreferenceComplianceEngine.Input]
    ) -> [TrendPoint] {
        struct Bucket {
            var followed = 0
            var violated = 0
        }
        var buckets: [String: Bucket] = [:]
        var coverageByKey: [String: Set<String>] = [:]
        var unevaluatedByKey: [String: Int] = [:]
        for check in checks {
            let key = keyFn(check)
            var bucket = buckets[key] ?? Bucket()
            switch check.outcome {
            case .followed:
                bucket.followed += 1
            case .violated:
                bucket.violated += 1
            case .unevaluated:
                unevaluatedByKey[key, default: 0] += 1
            case .notApplicable:
                break
            }
            buckets[key] = bucket
        }
        var tradesByKey: [String: Set<String>] = [:]

        for input in ordered {
            let periodKey = inputKeyFn(input)
            let rules = rulesCache.rules(for: input)
            let fp = rulesFingerprint(rules)
            coverageByKey[periodKey, default: []].insert(fp)
            unevaluatedByKey[periodKey, default: 0] += unevaluatedChecks(for: input, rules: rules)
            if let tradeID = input.tradeID {
                tradesByKey[periodKey, default: []].insert(tradeID)
            }
        }

        let sortedKeys = buckets.keys.sorted()
        var points: [TrendPoint] = []
        points.reserveCapacity(sortedKeys.count)
        for key in sortedKeys {
            let bucket = buckets[key]!
            let evaluated = bucket.followed + bucket.violated
            let adherence: Double?
            if evaluated > 0 {
                adherence = round((Double(bucket.followed) / Double(evaluated)) * 1000) / 10
            } else {
                adherence = nil
            }
            let insufficient = evaluated < 3
            let coverage = coverageByKey[key]
            let note: String?
            if (coverage?.count ?? 0) > 1 {
                note = "Rule configuration changed during this period, compare cautiously."
            } else {
                note = nil
            }
            points.append(
                TrendPoint(
                    key: key,
                    label: labelFn(key),
                    adherencePercent: insufficient ? nil : adherence,
                    evaluated: evaluated,
                    followed: bucket.followed,
                    violations: bucket.violated,
                    unevaluatedChecks: unevaluatedByKey[key] ?? 0,
                    tradeCount: tradesByKey[key]?.count ?? 0,
                    insufficientData: insufficient,
                    coverageNote: note
                )
            )
        }
        return points
    }

    private static func unevaluatedChecks(
        for input: PreferenceComplianceEngine.Input,
        rules: ResolvedTradingPreferences,
        allowedRuleIDs: Set<RuleID>? = nil
    ) -> Int {
        var unevaluated = 0
        if allows(rule: .preferredSession, in: allowedRuleIDs),
           !rules.preferredSessions.isEmpty, input.session == nil
        {
            unevaluated += 1
        }
        if allows(rule: .primaryInstrument, in: allowedRuleIDs),
           !rules.primaryInstruments.isEmpty, input.symbol == nil
        {
            unevaluated += 1
        }
        if allows(rule: .plannedHours, in: allowedRuleIDs),
           rules.plannedHours != nil, input.easternMinute < 0
        {
            unevaluated += 1
        }
        if allows(rule: .allowedTradingDay, in: allowedRuleIDs),
           !rules.allowedTradingDays.isEmpty, input.weekday == nil
        {
            unevaluated += 1
        }
        if allows(rule: .minPlannedRr, in: allowedRuleIDs),
           rules.minAcceptableRr != nil, input.plannedRr == nil
        {
            unevaluated += 1
        }
        if allows(rule: .maxContracts, in: allowedRuleIDs),
           rules.maxContractsPerTrade != nil, input.contracts == nil
        {
            unevaluated += 1
        }
        if allows(rule: .maxRiskPerTrade, in: allowedRuleIDs),
           rules.maxRiskPerTrade != nil, input.dollarRisk == nil
        {
            unevaluated += 1
        }
        if allows(rule: .targetRrMax, in: allowedRuleIDs),
           rules.targetRr != nil, input.maxRr == nil
        {
            unevaluated += 1
        }
        return unevaluated
    }

    private static func allows(rule: RuleID, in allowedRuleIDs: Set<RuleID>?) -> Bool {
        guard let allowedRuleIDs else { return true }
        return allowedRuleIDs.contains(rule)
    }

    private static func evaluateTradeLevelRules(
        input: PreferenceComplianceEngine.Input,
        rules: ResolvedTradingPreferences,
        state: inout BuildState
    ) {
        if !rules.preferredSessions.isEmpty, let session = input.session {
            let inside = rules.preferredSessions.contains(session)
            let detail: String
            if inside {
                detail = "Traded during \(session)."
            } else {
                detail = "Traded during \(session), outside preferred sessions."
            }
            state.recordTrade(
                rule: .preferredSession,
                input: input,
                outcome: inside ? .followed : .violated,
                level: .trade,
                scope: nil,
                detail: detail
            )
        }

        if !rules.primaryInstruments.isEmpty, let symbol = input.symbol {
            let inside = rules.primaryInstruments.contains(symbol)
            let detail: String
            if inside {
                detail = "\(symbol) is a primary instrument."
            } else {
                detail = "\(symbol) is outside primary instruments."
            }
            state.recordTrade(
                rule: .primaryInstrument,
                input: input,
                outcome: inside ? .followed : .violated,
                level: .trade,
                scope: nil,
                detail: detail
            )
        }

        if let hours = rules.plannedHours, input.easternMinute >= 0 {
            let inside = minuteInWindow(input.easternMinute, start: hours.startMinute, end: hours.endMinute)
            let detail = inside ? "Entry during planned hours." : "Entry outside planned hours."
            state.recordTrade(
                rule: .plannedHours,
                input: input,
                outcome: inside ? .followed : .violated,
                level: .trade,
                scope: nil,
                detail: detail
            )
        }

        if !rules.allowedTradingDays.isEmpty, let weekday = input.weekday {
            let inside = rules.allowedTradingDays.contains(weekday)
            let detail: String
            if inside {
                detail = "Traded on \(weekday.displayLabel)."
            } else {
                detail = "Traded on \(weekday.displayLabel), outside allowed days."
            }
            state.recordTrade(
                rule: .allowedTradingDay,
                input: input,
                outcome: inside ? .followed : .violated,
                level: .trade,
                scope: nil,
                detail: detail
            )
        }

        if let minRr = rules.minAcceptableRr, let planned = input.plannedRr {
            let ok = planned >= minRr
            let detail: String
            if ok {
                detail = "Planned R:R \(planned) met minimum \(minRr)."
            } else {
                detail = "Planned R:R \(planned) below minimum \(minRr)."
            }
            state.recordTrade(
                rule: .minPlannedRr,
                input: input,
                outcome: ok ? .followed : .violated,
                level: .trade,
                scope: nil,
                detail: detail
            )
        }

        if let cap = rules.maxContractsPerTrade, let contracts = input.contracts {
            let ok = contracts <= cap
            let detail: String
            if ok {
                detail = "\(contracts) contracts within cap \(cap)."
            } else {
                detail = "\(contracts) contracts above cap \(cap)."
            }
            state.recordTrade(
                rule: .maxContracts,
                input: input,
                outcome: ok ? .followed : .violated,
                level: .trade,
                scope: nil,
                detail: detail
            )
        }

        if let maxRisk = rules.maxRiskPerTrade, let risk = input.dollarRisk {
            let ok = risk <= maxRisk
            let detail: String
            if ok {
                detail = "Planned risk \(formatMoney(risk)) within \(formatMoney(maxRisk))."
            } else {
                detail = "Planned risk \(formatMoney(risk)) above \(formatMoney(maxRisk))."
            }
            state.recordTrade(
                rule: .maxRiskPerTrade,
                input: input,
                outcome: ok ? .followed : .violated,
                level: .trade,
                scope: nil,
                detail: detail
            )
        }

        if let target = rules.targetRr, let maxRr = input.maxRr {
            let ok = maxRr >= target
            let detail: String
            if ok {
                detail = "Max R \(maxRr) reached target \(target)."
            } else {
                detail = "Max R \(maxRr) below target \(target)."
            }
            state.recordTrade(
                rule: .targetRrMax,
                input: input,
                outcome: ok ? .followed : .violated,
                level: .trade,
                scope: nil,
                detail: detail
            )
        }
    }

    private static func collectScopedBuckets(
        for input: PreferenceComplianceEngine.Input,
        rules: ResolvedTradingPreferences,
        buckets: inout ScopedBuckets
    ) {
        let capKey = TradingRuleScopeMath.scopedDayBucket(
            dayKey: input.dayKey,
            accountID: input.accountID,
            scope: rules.maxTradesPerDayScope
        )
        buckets.capDay[capKey, default: []].append(input)

        let lossKey = TradingRuleScopeMath.scopedDayBucket(
            dayKey: input.dayKey,
            accountID: input.accountID,
            scope: rules.dailyLossLimitScope
        )
        buckets.lossDay[lossKey, default: []].append(input)

        let profitKey = TradingRuleScopeMath.scopedDayBucket(
            dayKey: input.dayKey,
            accountID: input.accountID,
            scope: rules.dailyProfitRulesScope
        )
        buckets.profitDay[profitKey, default: []].append(input)

        if let weekKey = input.weekKey {
            let scopedWeek = TradingRuleScopeMath.scopedWeekBucket(
                weekKey: weekKey,
                accountID: input.accountID,
                scope: rules.maxWeeklyLossScope
            )
            buckets.week[scopedWeek, default: []].append(input)
        }
    }

    private static func evaluateDailyTradeCaps(
        buckets: ScopedBuckets,
        rulesCache: TradingRulesResolvedRulesCache,
        state: inout BuildState
    ) {
        let scopeLabel = TradingRuleScopeMath.scopeBucketLabel
        for day in buckets.capDay.values {
            let sorted = day.sorted { $0.at < $1.at }
            for (index, input) in sorted.enumerated() {
                let rules = rulesCache.rules(for: input)
                guard let cap = rules.maxTradesPerDay else { continue }
                let over = index + 1 > cap
                let scope = scopeLabel(rules.maxTradesPerDayScope)
                let detail: String
                if over {
                    detail = "Trade #\(index + 1) on \(input.dayKey) exceeds cap \(cap)."
                } else {
                    detail = "Trade #\(index + 1) on \(input.dayKey) within cap \(cap)."
                }
                state.recordTrade(
                    rule: .maxTradesPerDay,
                    input: input,
                    outcome: over ? .violated : .followed,
                    level: .trade,
                    scope: scope,
                    detail: detail
                )
            }
        }
    }

    private static func evaluateDailyLossLimits(
        buckets: ScopedBuckets,
        rulesCache: TradingRulesResolvedRulesCache,
        state: inout BuildState
    ) {
        let scopeLabel = TradingRuleScopeMath.scopeBucketLabel
        for day in buckets.lossDay.values {
            let sorted = day.sorted { $0.at < $1.at }
            var running = 0.0
            var breached = false
            for input in sorted {
                let rules = rulesCache.rules(for: input)
                guard let limit = rules.dailyLossLimit else { continue }
                if let pnl = input.pnl { running += pnl }
                let scope = scopeLabel(rules.dailyLossLimitScope)
                if !breached && running <= -limit {
                    breached = true
                    state.pushCheck(
                        rule: .dailyLossLimit,
                        outcome: .violated,
                        level: .day,
                        input: input,
                        scope: scope,
                        detail: "Daily loss limit \(formatMoney(limit)) crossed on \(input.dayKey)."
                    )
                    continue
                }
                if breached {
                    state.recordTrade(
                        rule: .dailyLossLimit,
                        input: input,
                        outcome: .violated,
                        level: .trade,
                        scope: scope,
                        detail: "Trade after daily loss limit was crossed (\(input.dayKey))."
                    )
                }
            }
        }
    }

    private static func evaluateDailyProfitStops(
        buckets: ScopedBuckets,
        rulesCache: TradingRulesResolvedRulesCache,
        state: inout BuildState
    ) {
        let scopeLabel = TradingRuleScopeMath.scopeBucketLabel
        for day in buckets.profitDay.values {
            let sorted = day.sorted { $0.at < $1.at }
            var running = 0.0
            var hit = false
            for input in sorted {
                let rules = rulesCache.rules(for: input)
                guard rules.stopAfterDailyProfitTarget, let target = rules.dailyProfitTarget else { continue }
                let scope = scopeLabel(rules.dailyProfitRulesScope)
                if hit {
                    state.recordTrade(
                        rule: .dailyProfitStop,
                        input: input,
                        outcome: .violated,
                        level: .trade,
                        scope: scope,
                        detail: "Trade after daily profit target (\(formatMoney(target))) was reached."
                    )
                }
                if let pnl = input.pnl { running += pnl }
                if !hit && running >= target { hit = true }
            }
        }
    }

    private static func evaluateWeeklyLossLimits(
        buckets: ScopedBuckets,
        rulesCache: TradingRulesResolvedRulesCache,
        state: inout BuildState
    ) {
        let scopeLabel = TradingRuleScopeMath.scopeBucketLabel
        for week in buckets.week.values {
            let sorted = week.sorted { $0.at < $1.at }
            var running = 0.0
            var breached = false
            for input in sorted {
                let rules = rulesCache.rules(for: input)
                guard let limit = rules.maxWeeklyLoss else { continue }
                let scope = scopeLabel(rules.maxWeeklyLossScope)
                if breached {
                    state.recordTrade(
                        rule: .weeklyLossLimit,
                        input: input,
                        outcome: .violated,
                        level: .trade,
                        scope: scope,
                        detail: "Trade after weekly loss limit (\(formatMoney(limit))) was crossed."
                    )
                    continue
                }
                if let pnl = input.pnl { running += pnl }
                if running <= -limit {
                    breached = true
                    let weekLabel = input.weekKey ?? "–"
                    state.pushCheck(
                        rule: .weeklyLossLimit,
                        outcome: .violated,
                        level: .week,
                        input: input,
                        scope: scope,
                        detail: "Weekly loss limit \(formatMoney(limit)) crossed (Eastern week \(weekLabel))."
                    )
                }
            }
        }
    }

    private static func countUnevaluated(
        inputs: [PreferenceComplianceEngine.Input],
        rulesCache: TradingRulesResolvedRulesCache,
        allowedRuleIDs: Set<RuleID>? = nil
    ) -> Int {
        inputs.reduce(0) { partial, input in
            partial + unevaluatedChecks(
                for: input,
                rules: rulesCache.rules(for: input),
                allowedRuleIDs: allowedRuleIDs
            )
        }
    }

    private static func makeScore(from checks: [Check], unevaluatedFieldGaps: Int) -> Score {
        var followed = 0
        var violated = 0
        var unevaluatedFromChecks = 0
        for check in checks {
            switch check.outcome {
            case .followed:
                followed += 1
            case .violated:
                violated += 1
            case .unevaluated:
                unevaluatedFromChecks += 1
            case .notApplicable:
                break
            }
        }
        let evaluated = followed + violated
        let unevaluated = unevaluatedFieldGaps + unevaluatedFromChecks
        let adherenceRaw: Double?
        if evaluated > 0 {
            adherenceRaw = (Double(followed) / Double(evaluated)) * 100
        } else {
            adherenceRaw = nil
        }
        let adherencePercent = adherenceRaw.map { round($0 * 10) / 10 }
        return Score(
            adherencePercent: adherencePercent,
            followed: followed,
            violated: violated,
            unevaluated: unevaluated,
            evaluated: evaluated,
            explanation:
                "Adherence % = rules followed ÷ (followed + violations) among checks we could evaluate with reliable data. Unevaluated checks are excluded, never counted as compliant. Not-applicable checks are excluded from adherence and unevaluated counts."
        )
    }

    private static func makeViolationEvents(from checks: [Check]) -> [ViolationEvent] {
        let violated = checks.filter { $0.outcome == .violated }
        let sorted = violated.sorted { $0.at > $1.at }
        var events: [ViolationEvent] = []
        events.reserveCapacity(sorted.count)
        for check in sorted {
            events.append(
                ViolationEvent(
                    id: check.id,
                    at: check.at,
                    dayKey: check.dayKey,
                    tradeID: check.tradeID,
                    accountID: check.accountID,
                    ruleID: check.ruleID,
                    ruleLabel: check.ruleID.label,
                    level: check.level,
                    scopeLabel: check.scopeLabel,
                    summary: check.detail
                )
            )
        }
        return events
    }

    struct CheckEvaluation: Sendable {
        var checks: [Check]
        var unevaluatedFieldGaps: Int
    }

    static func complianceInputs(from trades: [Trade]) -> [PreferenceComplianceEngine.Input] {
        guard !trades.isEmpty else { return [] }
        var chronological = true
        if trades.count > 1 {
            for index in 1 ..< trades.count where trades[index].entryAt < trades[index - 1].entryAt {
                chronological = false
                break
            }
        }
        let mapped = trades.map(PreferenceComplianceEngine.input(from:))
        guard chronological else {
            return mapped.sorted { $0.at < $1.at }
        }
        return mapped
    }

    static func evaluateChecks(
        inputs: [PreferenceComplianceEngine.Input],
        context: PreferenceRuleContext?,
        rulesCache: TradingRulesResolvedRulesCache,
        trades: [Trade],
        psychologyContextTrades: [Trade]
    ) -> CheckEvaluation {
        var state = BuildState()
        var buckets = ScopedBuckets()

        for (index, input) in inputs.enumerated() {
            let rules = rulesCache.rules(at: index)
            evaluateTradeLevelRules(input: input, rules: rules, state: &state)
            collectScopedBuckets(for: input, rules: rules, buckets: &buckets)
        }

        evaluateDailyTradeCaps(buckets: buckets, rulesCache: rulesCache, state: &state)
        evaluateDailyLossLimits(buckets: buckets, rulesCache: rulesCache, state: &state)
        evaluateDailyProfitStops(buckets: buckets, rulesCache: rulesCache, state: &state)
        evaluateWeeklyLossLimits(buckets: buckets, rulesCache: rulesCache, state: &state)

        let scopedIDs = Set(trades.map(\.id.rawValue))
        let psychologyContext = psychologyContextTrades.isEmpty ? trades : psychologyContextTrades
        TradingRulesPsychologyCompliance.evaluate(
            contextTrades: psychologyContext,
            scopedTradeIDs: scopedIDs,
            context: context,
            state: &state
        )

        let unevaluatedFieldGaps = countUnevaluated(inputs: inputs, rulesCache: rulesCache)
        return CheckEvaluation(checks: state.checks, unevaluatedFieldGaps: unevaluatedFieldGaps)
    }

    static func buildDisciplinePriorMetrics(
        trades: [Trade],
        context: PreferenceRuleContext?,
        psychologyContextTrades: [Trade],
        allowedRuleIDs: Set<RuleID>? = nil
    ) -> TradingRulesDisciplineProgress.PriorMetrics? {
        guard !trades.isEmpty else { return nil }
        let inputs = complianceInputs(from: trades)
        let rulesCache = TradingRulesResolvedRulesCache(context: context, inputs: inputs)
        let evaluation = evaluateChecks(
            inputs: inputs,
            context: context,
            rulesCache: rulesCache,
            trades: trades,
            psychologyContextTrades: psychologyContextTrades
        )
        let activeChecks = TradingRulesPlanTier.filterChecks(evaluation.checks, allowedRuleIDs: allowedRuleIDs)
        let gaps = allowedRuleIDs == nil
            ? evaluation.unevaluatedFieldGaps
            : countUnevaluated(inputs: inputs, rulesCache: rulesCache, allowedRuleIDs: allowedRuleIDs)
        let score = makeScore(from: activeChecks, unevaluatedFieldGaps: gaps)
        return TradingRulesDisciplineProgress.PriorMetrics(score: score, checks: activeChecks)
    }

    static func build(
        trades: [Trade],
        context: PreferenceRuleContext?,
        psychologyContextTrades: [Trade] = [],
        priorDisciplineMetrics: TradingRulesDisciplineProgress.PriorMetrics? = nil,
        complianceGoalPercent: Double = TradingRulesDisciplineProgress.defaultGoalPercent,
        allowedRuleIDs: Set<RuleID>? = nil
    ) -> Result {
        let inputs = complianceInputs(from: trades)
        let rulesCache = TradingRulesResolvedRulesCache(context: context, inputs: inputs)
        return build(
            inputs: inputs,
            context: context,
            rulesCache: rulesCache,
            trades: trades,
            psychologyContextTrades: psychologyContextTrades,
            priorDisciplineMetrics: priorDisciplineMetrics,
            complianceGoalPercent: complianceGoalPercent,
            allowedRuleIDs: allowedRuleIDs
        )
    }

    static func build(
        inputs: [PreferenceComplianceEngine.Input],
        context: PreferenceRuleContext?,
        rulesCache: TradingRulesResolvedRulesCache,
        trades: [Trade] = [],
        psychologyContextTrades: [Trade] = [],
        priorDisciplineMetrics: TradingRulesDisciplineProgress.PriorMetrics? = nil,
        complianceGoalPercent: Double = TradingRulesDisciplineProgress.defaultGoalPercent,
        allowedRuleIDs: Set<RuleID>? = nil
    ) -> Result {
        let evaluation = evaluateChecks(
            inputs: inputs,
            context: context,
            rulesCache: rulesCache,
            trades: trades,
            psychologyContextTrades: psychologyContextTrades
        )
        let activeChecks = TradingRulesPlanTier.filterChecks(evaluation.checks, allowedRuleIDs: allowedRuleIDs)
        let unevaluatedGaps = allowedRuleIDs == nil
            ? evaluation.unevaluatedFieldGaps
            : countUnevaluated(
                inputs: inputs,
                rulesCache: rulesCache,
                allowedRuleIDs: allowedRuleIDs!
            )
        let score = makeScore(
            from: activeChecks,
            unevaluatedFieldGaps: unevaluatedGaps
        )
        let tradesByID = Dictionary(uniqueKeysWithValues: trades.map { ($0.id.rawValue, $0) })
        let impactRows = TradingRulesRuleImpact.buildImpactRows(
            checks: activeChecks,
            tradesByID: tradesByID
        )
        let impactHighlights = TradingRulesRuleImpact.comparisonHighlights(from: impactRows)
        let violationEvents = makeViolationEvents(from: activeChecks)

        let weeklyTrend = buildTrend(
            checks: activeChecks,
            keyFn: { check in check.weekKey ?? check.dayKey },
            inputKeyFn: { input in input.weekKey ?? input.dayKey },
            labelFn: { key in "Week of \(key)" },
            rulesCache: rulesCache,
            ordered: inputs
        )
        let monthlyTrend = buildTrend(
            checks: activeChecks,
            keyFn: { check in check.monthKey },
            inputKeyFn: { input in monthKey(input.dayKey) },
            labelFn: { key in key },
            rulesCache: rulesCache,
            ordered: inputs
        )

        let usesHistoricalRevisions = !(context?.revisions.isEmpty ?? true)
        let retrospectivelyEvaluatedTrades = inputs.reduce(into: 0) { count, input in
            if PreferenceComplianceEngine.usesRetrospectiveRuleApplication(
                in: context,
                at: input.at,
                accountID: input.accountID
            ) {
                count += 1
            }
        }
        let violationPatterns = TradingRulesViolationPatterns.build(
            checks: activeChecks,
            inputs: inputs,
            rulesCache: rulesCache
        )
        let disciplineProgress = TradingRulesDisciplineProgress.build(
            currentScore: score,
            currentChecks: activeChecks,
            currentWeekly: weeklyTrend,
            prior: priorDisciplineMetrics,
            goalPercent: complianceGoalPercent
        )
        return Result(
            score: score,
            impacts: impactRows,
            violations: violationEvents,
            weeklyTrend: weeklyTrend,
            monthlyTrend: monthlyTrend,
            usesHistoricalRevisions: usesHistoricalRevisions,
            retrospectivelyEvaluatedTrades: retrospectivelyEvaluatedTrades,
            violationPatterns: violationPatterns,
            complianceChecks: activeChecks,
            impactHighlights: impactHighlights,
            disciplineProgress: disciplineProgress
        )
    }
}
