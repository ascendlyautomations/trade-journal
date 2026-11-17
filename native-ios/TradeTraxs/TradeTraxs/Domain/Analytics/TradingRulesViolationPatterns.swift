import Foundation

/// Derived violation pattern analytics — built from compliance checks (not a second engine).
nonisolated enum TradingRulesViolationPatterns {
    static let worstDayMinimumEvaluatedChecks = 3
    static let recurringMinimumEvaluatedDays = 3
    static let recurringMinimumViolatedDays = 2
    static let defaultMostBrokenLimit = 5
    static let defaultWorstDayLimit = 3
    static let recurringLookbackEvaluatedDays = 7

    struct MostBrokenRuleRow: Identifiable, Sendable, Hashable {
        var id: String { ruleID.rawValue }
        var ruleID: TradingRulesComplianceAnalytics.RuleID
        var ruleLabel: String
        var violated: Int
        var followed: Int
        var evaluated: Int
        var violationRatePercent: Double?

        var accessibilitySummary: String {
            let rate = violationRatePercent.map { String(format: "%.1f%%", $0) } ?? "—"
            return "\(ruleLabel): \(violated) violations, \(rate) rate, \(evaluated) checks"
        }
    }

    struct WorstTradingDayRow: Identifiable, Sendable, Hashable {
        var id: String { dayKey }
        var dayKey: String
        var displayDate: String
        var violated: Int
        var evaluated: Int
        var violationRatePercent: Double
    }

    struct RecurringPatternSummary: Identifiable, Sendable, Hashable {
        var id: String { ruleID.rawValue }
        var ruleID: TradingRulesComplianceAnalytics.RuleID
        var ruleLabel: String
        var violatedDays: Int
        var evaluatedDaysInWindow: Int
        var summary: String
    }

    struct RuleDrillDownSnapshot: Sendable {
        var ruleID: TradingRulesComplianceAnalytics.RuleID
        var ruleLabel: String
        var followed: Int
        var violated: Int
        var unevaluated: Int
        var evaluated: Int
        var adherencePercent: Double?
        var weeklyTrend: [TradingRulesComplianceAnalytics.TrendPoint]
        var violations: [TradingRulesComplianceAnalytics.ViolationEvent]
    }

    struct Bundle: Sendable {
        var mostBrokenRules: [MostBrokenRuleRow]
        var worstTradingDays: [WorstTradingDayRow]
        var recurringPatterns: [RecurringPatternSummary]
        var ruleDrillDown: [TradingRulesComplianceAnalytics.RuleID: RuleDrillDownSnapshot]

        static let empty = Bundle(
            mostBrokenRules: [],
            worstTradingDays: [],
            recurringPatterns: [],
            ruleDrillDown: [:]
        )
    }

    static func build(
        checks: [TradingRulesComplianceAnalytics.Check],
        inputs: [PreferenceComplianceEngine.Input],
        rulesCache: TradingRulesResolvedRulesCache
    ) -> Bundle {
        guard !checks.isEmpty || !inputs.isEmpty else { return .empty }

        var ruleStats: [TradingRulesComplianceAnalytics.RuleID: (followed: Int, violated: Int)] = [:]
        for rule in TradingRulesComplianceAnalytics.RuleID.allCases {
            ruleStats[rule] = (0, 0)
        }
        var ruleUnevaluated: [TradingRulesComplianceAnalytics.RuleID: Int] = [:]
        for rule in TradingRulesComplianceAnalytics.RuleID.allCases {
            ruleUnevaluated[rule] = 0
        }

        for check in checks {
            guard var bucket = ruleStats[check.ruleID] else { continue }
            switch check.outcome {
            case .followed:
                bucket.followed += 1
            case .violated:
                bucket.violated += 1
            case .unevaluated:
                ruleUnevaluated[check.ruleID, default: 0] += 1
            case .notApplicable:
                break
            }
            ruleStats[check.ruleID] = bucket
        }
        for (index, input) in inputs.enumerated() {
            let rules = rulesCache.rules(at: index)
            ruleUnevaluated[.preferredSession, default: 0] +=
                unevaluatedIncrement(ruleActive: !rules.preferredSessions.isEmpty, missing: input.session == nil)
            ruleUnevaluated[.primaryInstrument, default: 0] +=
                unevaluatedIncrement(ruleActive: !rules.primaryInstruments.isEmpty, missing: input.symbol == nil)
            ruleUnevaluated[.plannedHours, default: 0] +=
                unevaluatedIncrement(ruleActive: rules.plannedHours != nil, missing: input.easternMinute < 0)
            ruleUnevaluated[.allowedTradingDay, default: 0] +=
                unevaluatedIncrement(ruleActive: !rules.allowedTradingDays.isEmpty, missing: input.weekday == nil)
            ruleUnevaluated[.minPlannedRr, default: 0] +=
                unevaluatedIncrement(ruleActive: rules.minAcceptableRr != nil, missing: input.plannedRr == nil)
            ruleUnevaluated[.maxContracts, default: 0] +=
                unevaluatedIncrement(ruleActive: rules.maxContractsPerTrade != nil, missing: input.contracts == nil)
            ruleUnevaluated[.maxRiskPerTrade, default: 0] +=
                unevaluatedIncrement(ruleActive: rules.maxRiskPerTrade != nil, missing: input.dollarRisk == nil)
            ruleUnevaluated[.targetRrMax, default: 0] +=
                unevaluatedIncrement(ruleActive: rules.targetRr != nil, missing: input.maxRr == nil)
        }

        let mostBroken = buildMostBrokenRules(ruleStats: ruleStats)

        let dayStats = buildDayStats(checks: checks)
        let worstDays = buildWorstDays(dayStats: dayStats)

        let recurring = buildRecurringPatterns(checks: checks, ruleStats: ruleStats)

        let drillDown = buildRuleDrillDown(
            checks: checks,
            ruleStats: ruleStats,
            ruleUnevaluated: ruleUnevaluated,
            inputs: inputs
        )

        return Bundle(
            mostBrokenRules: mostBroken,
            worstTradingDays: worstDays,
            recurringPatterns: recurring,
            ruleDrillDown: drillDown
        )
    }

    private static func unevaluatedIncrement(ruleActive: Bool, missing: Bool) -> Int {
        ruleActive && missing ? 1 : 0
    }

    private static func buildMostBrokenRules(
        ruleStats: [TradingRulesComplianceAnalytics.RuleID: (followed: Int, violated: Int)]
    ) -> [MostBrokenRuleRow] {
        var rows: [MostBrokenRuleRow] = []
        rows.reserveCapacity(ruleStats.count)
        for rule in TradingRulesComplianceAnalytics.RuleID.allCases {
            guard let stats = ruleStats[rule] else { continue }
            let evaluated = stats.followed + stats.violated
            guard evaluated > 0 else { continue }
            let rate = round((Double(stats.violated) / Double(evaluated)) * 1000) / 10
            rows.append(
                MostBrokenRuleRow(
                    ruleID: rule,
                    ruleLabel: rule.label,
                    violated: stats.violated,
                    followed: stats.followed,
                    evaluated: evaluated,
                    violationRatePercent: rate
                )
            )
        }
        return rows.sorted { lhs, rhs in
            let lr = lhs.violationRatePercent ?? 0
            let rr = rhs.violationRatePercent ?? 0
            if lr != rr { return lr > rr }
            if lhs.violated != rhs.violated { return lhs.violated > rhs.violated }
            return lhs.ruleLabel < rhs.ruleLabel
        }
    }

    private struct DayBucket {
        var followed = 0
        var violated = 0
    }

    private static func buildDayStats(
        checks: [TradingRulesComplianceAnalytics.Check]
    ) -> [String: DayBucket] {
        var map: [String: DayBucket] = [:]
        for check in checks {
            var bucket = map[check.dayKey] ?? DayBucket()
            switch check.outcome {
            case .followed:
                bucket.followed += 1
            case .violated:
                bucket.violated += 1
            case .unevaluated, .notApplicable:
                break
            }
            map[check.dayKey] = bucket
        }
        return map
    }

    private static func buildWorstDays(dayStats: [String: DayBucket]) -> [WorstTradingDayRow] {
        var rows: [WorstTradingDayRow] = []
        for (dayKey, bucket) in dayStats {
            let evaluated = bucket.followed + bucket.violated
            guard evaluated >= worstDayMinimumEvaluatedChecks else { continue }
            let rate = round((Double(bucket.violated) / Double(evaluated)) * 1000) / 10
            rows.append(
                WorstTradingDayRow(
                    dayKey: dayKey,
                    displayDate: displayDayKey(dayKey),
                    violated: bucket.violated,
                    evaluated: evaluated,
                    violationRatePercent: rate
                )
            )
        }
        return rows.sorted { lhs, rhs in
            if lhs.violationRatePercent != rhs.violationRatePercent {
                return lhs.violationRatePercent > rhs.violationRatePercent
            }
            if lhs.violated != rhs.violated { return lhs.violated > rhs.violated }
            return lhs.dayKey > rhs.dayKey
        }
        .prefix(defaultWorstDayLimit)
        .map { $0 }
    }

    private static func buildRecurringPatterns(
        checks: [TradingRulesComplianceAnalytics.Check],
        ruleStats: [TradingRulesComplianceAnalytics.RuleID: (followed: Int, violated: Int)]
    ) -> [RecurringPatternSummary] {
        var ruleDays: [TradingRulesComplianceAnalytics.RuleID: [String: (violated: Bool, evaluated: Bool)]] = [:]
        for check in checks {
            var days = ruleDays[check.ruleID] ?? [:]
            var entry = days[check.dayKey] ?? (false, false)
            entry.evaluated = true
            if check.outcome == .violated { entry.violated = true }
            days[check.dayKey] = entry
            ruleDays[check.ruleID] = days
        }

        var summaries: [RecurringPatternSummary] = []
        for rule in TradingRulesComplianceAnalytics.RuleID.allCases {
            guard let stats = ruleStats[rule], stats.violated > 0 else { continue }
            guard let days = ruleDays[rule] else { continue }
            let sortedEvaluatedDays = days.keys.filter { days[$0]?.evaluated == true }.sorted()
            let window = Array(sortedEvaluatedDays.suffix(recurringLookbackEvaluatedDays))
            guard window.count >= recurringMinimumEvaluatedDays else { continue }
            let violatedInWindow = window.filter { days[$0]?.violated == true }.count
            guard violatedInWindow >= recurringMinimumViolatedDays else { continue }
            summaries.append(
                RecurringPatternSummary(
                    ruleID: rule,
                    ruleLabel: rule.label,
                    violatedDays: violatedInWindow,
                    evaluatedDaysInWindow: window.count,
                    summary:
                        "\(rule.label) violated on \(violatedInWindow) of your last \(window.count) evaluated trading days."
                )
            )
        }
        return summaries.sorted { $0.violatedDays > $1.violatedDays }
    }

    private static func buildRuleDrillDown(
        checks: [TradingRulesComplianceAnalytics.Check],
        ruleStats: [TradingRulesComplianceAnalytics.RuleID: (followed: Int, violated: Int)],
        ruleUnevaluated: [TradingRulesComplianceAnalytics.RuleID: Int],
        inputs: [PreferenceComplianceEngine.Input]
    ) -> [TradingRulesComplianceAnalytics.RuleID: RuleDrillDownSnapshot] {
        var map: [TradingRulesComplianceAnalytics.RuleID: RuleDrillDownSnapshot] = [:]
        for rule in TradingRulesComplianceAnalytics.RuleID.allCases {
            guard let stats = ruleStats[rule] else { continue }
            let evaluated = stats.followed + stats.violated
            let unevaluated = ruleUnevaluated[rule] ?? 0
            guard evaluated > 0 || unevaluated > 0 else { continue }

            let adherence: Double?
            if evaluated > 0 {
                adherence = round((Double(stats.followed) / Double(evaluated)) * 1000) / 10
            } else {
                adherence = nil
            }

            let ruleChecks = checks.filter { $0.ruleID == rule }
            let weeklyTrend = buildRuleWeeklyTrend(checks: ruleChecks, inputs: inputs)
            let violations = violationEvents(from: ruleChecks)

            map[rule] = RuleDrillDownSnapshot(
                ruleID: rule,
                ruleLabel: rule.label,
                followed: stats.followed,
                violated: stats.violated,
                unevaluated: unevaluated,
                evaluated: evaluated,
                adherencePercent: adherence,
                weeklyTrend: weeklyTrend,
                violations: violations
            )
        }
        return map
    }

    private static func buildRuleWeeklyTrend(
        checks: [TradingRulesComplianceAnalytics.Check],
        inputs: [PreferenceComplianceEngine.Input]
    ) -> [TradingRulesComplianceAnalytics.TrendPoint] {
        struct Bucket { var followed = 0; var violated = 0 }
        var buckets: [String: Bucket] = [:]
        for check in checks {
            let key = check.weekKey ?? check.dayKey
            var bucket = buckets[key] ?? Bucket()
            switch check.outcome {
            case .followed:
                bucket.followed += 1
            case .violated:
                bucket.violated += 1
            case .unevaluated, .notApplicable:
                break
            }
            buckets[key] = bucket
        }

        var tradeCountByKey: [String: Set<String>] = [:]
        let checkKeys = Set(checks.map { $0.weekKey ?? $0.dayKey })
        for input in inputs {
            let key = input.weekKey ?? input.dayKey
            guard checkKeys.contains(key), let tradeID = input.tradeID else { continue }
            tradeCountByKey[key, default: []].insert(tradeID)
        }

        return buckets.keys.sorted().map { key in
            let bucket = buckets[key]!
            let evaluated = bucket.followed + bucket.violated
            let adherence: Double?
            if evaluated > 0 {
                adherence = round((Double(bucket.followed) / Double(evaluated)) * 1000) / 10
            } else {
                adherence = nil
            }
            let insufficient = evaluated < 3
            return TradingRulesComplianceAnalytics.TrendPoint(
                key: key,
                label: key.hasPrefix("Week") ? key : "Week of \(key)",
                adherencePercent: insufficient ? nil : adherence,
                evaluated: evaluated,
                followed: bucket.followed,
                violations: bucket.violated,
                unevaluatedChecks: 0,
                tradeCount: tradeCountByKey[key]?.count ?? 0,
                insufficientData: insufficient,
                coverageNote: nil
            )
        }
        .suffix(8)
        .map { $0 }
    }

    private static func violationEvents(
        from checks: [TradingRulesComplianceAnalytics.Check]
    ) -> [TradingRulesComplianceAnalytics.ViolationEvent] {
        let violated = checks.filter { $0.outcome == .violated }.sorted { $0.at > $1.at }
        return violated.map { check in
            TradingRulesComplianceAnalytics.ViolationEvent(
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
        }
    }

    static func violations(
        forDay dayKey: String,
        from checks: [TradingRulesComplianceAnalytics.Check]
    ) -> [TradingRulesComplianceAnalytics.ViolationEvent] {
        let dayChecks = checks.filter { $0.dayKey == dayKey && $0.outcome == .violated }
        return violationEvents(from: dayChecks)
    }

    private static func displayDayKey(_ dayKey: String) -> String {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return dayKey }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.timeZone = TimeZone(identifier: "America/New_York")
        guard let date = Calendar(identifier: .gregorian).date(from: components) else { return dayKey }
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
