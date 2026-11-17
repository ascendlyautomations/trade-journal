import Foundation

nonisolated enum TradingRulesDisciplineProgress {
    static let minimumEvaluatedChecksForPeriodCompare = 10
    static let minimumEvaluatedChecksPerDay = 3
    static let defaultGoalPercent = 90.0
    static let minimumEvaluatedChecksForRuleDelta = 5
    static let historyPointLimit = 12

    /// Lightweight prior-period payload for discipline deltas (no impact/trends/violation bundles).
    struct PriorMetrics: Sendable {
        var score: TradingRulesComplianceAnalytics.Score
        var checks: [TradingRulesComplianceAnalytics.Check]
    }

    struct Bundle: Sendable {
        var currentAdherencePercent: Double?
        var priorAdherencePercent: Double?
        var adherenceDeltaPoints: Double?
        var periodCompareSufficient: Bool
        var mostImprovedRule: RuleDelta?
        var mostDeclinedRule: RuleDelta?
        var goalPercent: Double
        var daysMeetingGoal: Int
        var evaluatedDaysInScope: Int
        var goalStreakDays: Int
        var historyPoints: [HistoryPoint]
        var insufficientData: Bool
    }

    struct RuleDelta: Sendable, Identifiable, Hashable {
        var id: String { ruleID.rawValue }
        var ruleID: TradingRulesComplianceAnalytics.RuleID
        var ruleLabel: String
        var currentViolationRatePercent: Double
        var priorViolationRatePercent: Double
        var deltaPoints: Double
    }

    struct HistoryPoint: Identifiable, Sendable, Hashable {
        var id: String { key }
        var key: String
        var label: String
        var adherencePercent: Double?
        var evaluated: Int
        var insufficientData: Bool
    }

    static let empty = Bundle(
        currentAdherencePercent: nil,
        priorAdherencePercent: nil,
        adherenceDeltaPoints: nil,
        periodCompareSufficient: false,
        mostImprovedRule: nil,
        mostDeclinedRule: nil,
        goalPercent: defaultGoalPercent,
        daysMeetingGoal: 0,
        evaluatedDaysInScope: 0,
        goalStreakDays: 0,
        historyPoints: [],
        insufficientData: true
    )

    static func priorTrades(
        ownerTrades: [Trade],
        accounts: [TradingAccount],
        scope: DashboardClientScopeFilter,
        now: Date = Date()
    ) -> [Trade] {
        guard let current = TradingRulesDisciplineScopeInterval.currentInterval(scope: scope, now: now),
              let priorInterval = TradingRulesDisciplineScopeInterval.priorInterval(matching: current)
        else {
            return []
        }

        var priorScope = scope
        priorScope.dateRange = .all
        priorScope.customInterval = priorInterval

        let scoped = PsychologyAnalyticsTradeScope.complianceScopedTrades(
            ownerTrades: ownerTrades,
            accounts: accounts,
            scope: priorScope
        )
        return scoped
    }

    static func build(
        currentScore: TradingRulesComplianceAnalytics.Score,
        currentChecks: [TradingRulesComplianceAnalytics.Check],
        currentWeekly: [TradingRulesComplianceAnalytics.TrendPoint],
        prior: PriorMetrics?,
        goalPercent: Double
    ) -> Bundle {
        let currentEvaluated = currentScore.evaluated
        let priorEvaluated = prior?.score.evaluated ?? 0
        let periodCompareSufficient =
            currentEvaluated >= minimumEvaluatedChecksForPeriodCompare
            && priorEvaluated >= minimumEvaluatedChecksForPeriodCompare

        var adherenceDelta: Double?
        if periodCompareSufficient,
           let currentPct = currentScore.adherencePercent,
           let priorPct = prior?.score.adherencePercent
        {
            adherenceDelta = round((currentPct - priorPct) * 10) / 10
        }

        let ruleDeltas = ruleViolationRateDeltas(currentChecks: currentChecks, prior: prior)
        let mostImproved = ruleDeltas.filter { $0.deltaPoints < 0 }.min(by: { $0.deltaPoints < $1.deltaPoints })
        let mostDeclined = ruleDeltas.filter { $0.deltaPoints > 0 }.max(by: { $0.deltaPoints < $1.deltaPoints })

        let dayStats = dailyAdherence(from: currentChecks)
        let evaluatedDays = dayStats.filter { $0.value.evaluated >= minimumEvaluatedChecksPerDay }
        let daysMeetingGoal = evaluatedDays.filter { ($0.value.adherence ?? 0) >= goalPercent }.count

        let sortedDayKeys = evaluatedDays.keys.sorted()
        var streak = 0
        for key in sortedDayKeys.reversed() {
            guard let adherence = evaluatedDays[key]?.adherence, adherence >= goalPercent else { break }
            streak += 1
        }

        let history = historyFromWeeks(currentWeekly)

        let insufficient = currentEvaluated < minimumEvaluatedChecksForPeriodCompare

        return Bundle(
            currentAdherencePercent: currentScore.adherencePercent,
            priorAdherencePercent: prior?.score.adherencePercent,
            adherenceDeltaPoints: adherenceDelta,
            periodCompareSufficient: periodCompareSufficient,
            mostImprovedRule: mostImproved,
            mostDeclinedRule: mostDeclined,
            goalPercent: goalPercent,
            daysMeetingGoal: daysMeetingGoal,
            evaluatedDaysInScope: evaluatedDays.count,
            goalStreakDays: streak,
            historyPoints: history,
            insufficientData: insufficient
        )
    }

    private struct DayBucket {
        var followed = 0
        var violated = 0
        var evaluated: Int { followed + violated }
        var adherence: Double? {
            guard evaluated > 0 else { return nil }
            return round((Double(followed) / Double(evaluated)) * 1000) / 10
        }
    }

    private static func dailyAdherence(
        from checks: [TradingRulesComplianceAnalytics.Check]
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

    private static func ruleViolationRateDeltas(
        currentChecks: [TradingRulesComplianceAnalytics.Check],
        prior: PriorMetrics?
    ) -> [RuleDelta] {
        guard let prior else { return [] }
        var deltas: [RuleDelta] = []
        let currentRates = violationRatesByRule(checks: currentChecks)
        let priorRates = violationRatesByRule(checks: prior.checks)

        for rule in TradingRulesComplianceAnalytics.RuleID.allCases {
            guard let currentRate = currentRates[rule],
                  let priorRate = priorRates[rule]
            else { continue }
            guard currentRate.evaluated >= minimumEvaluatedChecksForRuleDelta,
                  priorRate.evaluated >= minimumEvaluatedChecksForRuleDelta
            else { continue }
            let delta = round((currentRate.rate - priorRate.rate) * 10) / 10
            deltas.append(
                RuleDelta(
                    ruleID: rule,
                    ruleLabel: rule.label,
                    currentViolationRatePercent: currentRate.rate,
                    priorViolationRatePercent: priorRate.rate,
                    deltaPoints: delta
                )
            )
        }
        return deltas
    }

    private struct RuleRate {
        var rate: Double
        var evaluated: Int
    }

    private static func violationRatesByRule(
        checks: [TradingRulesComplianceAnalytics.Check]
    ) -> [TradingRulesComplianceAnalytics.RuleID: RuleRate] {
        var buckets: [TradingRulesComplianceAnalytics.RuleID: (followed: Int, violated: Int)] = [:]
        for rule in TradingRulesComplianceAnalytics.RuleID.allCases {
            buckets[rule] = (0, 0)
        }
        for check in checks {
            guard var bucket = buckets[check.ruleID] else { continue }
            switch check.outcome {
            case .followed:
                bucket.followed += 1
            case .violated:
                bucket.violated += 1
            case .unevaluated, .notApplicable:
                break
            }
            buckets[check.ruleID] = bucket
        }
        var result: [TradingRulesComplianceAnalytics.RuleID: RuleRate] = [:]
        for (rule, bucket) in buckets {
            let evaluated = bucket.followed + bucket.violated
            guard evaluated > 0 else { continue }
            let rate = round((Double(bucket.violated) / Double(evaluated)) * 1000) / 10
            result[rule] = RuleRate(rate: rate, evaluated: evaluated)
        }
        return result
    }

    private static func historyFromWeeks(
        _ weekly: [TradingRulesComplianceAnalytics.TrendPoint]
    ) -> [HistoryPoint] {
        Array(
            weekly.suffix(historyPointLimit).map { point in
                HistoryPoint(
                    key: point.key,
                    label: point.label,
                    adherencePercent: point.adherencePercent,
                    evaluated: point.evaluated,
                    insufficientData: point.insufficientData
                )
            }
        )
    }
}
