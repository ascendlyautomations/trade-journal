import XCTest
@testable import TradeTraxs

final class TradingRulesViolationPatternsTests: XCTestCase {
  private let base = Date(timeIntervalSince1970: 1_800_000_000)

    func testMostBrokenRanksByViolationRateThenCount() {
        let checks: [TradingRulesComplianceAnalytics.Check] = [
            check(rule: .maxContracts, outcome: .violated, day: "2026-01-01"),
            check(rule: .maxContracts, outcome: .violated, day: "2026-01-01"),
            check(rule: .maxContracts, outcome: .followed, day: "2026-01-02"),
            check(rule: .preferredSession, outcome: .violated, day: "2026-01-01"),
            check(rule: .preferredSession, outcome: .followed, day: "2026-01-02"),
            check(rule: .preferredSession, outcome: .followed, day: "2026-01-03"),
            check(rule: .preferredSession, outcome: .followed, day: "2026-01-04"),
        ]
        let bundle = TradingRulesViolationPatterns.build(checks: checks, inputs: [], rulesCache: .noop)
        let rows = bundle.mostBrokenRules
        XCTAssertEqual(rows.first?.ruleID, .maxContracts)
        XCTAssertEqual(rows.first?.violationRatePercent, 66.7)
        XCTAssertEqual(rows.first?.evaluated, 3)
    }

    func testWorstDaysRequiresMinimumEvaluatedChecks() {
        let checks: [TradingRulesComplianceAnalytics.Check] = [
            check(rule: .maxContracts, outcome: .violated, day: "2026-01-01"),
            check(rule: .maxContracts, outcome: .violated, day: "2026-01-01"),
            check(rule: .maxContracts, outcome: .followed, day: "2026-01-02"),
            check(rule: .preferredSession, outcome: .violated, day: "2026-01-03"),
        ]
        let bundle = TradingRulesViolationPatterns.build(checks: checks, inputs: [], rulesCache: .noop)
        XCTAssertTrue(bundle.worstTradingDays.isEmpty)
    }

    func testWorstDaysRanksByViolationRate() {
        let checks: [TradingRulesComplianceAnalytics.Check] = [
            check(rule: .maxContracts, outcome: .violated, day: "2026-01-01"),
            check(rule: .maxContracts, outcome: .violated, day: "2026-01-01"),
            check(rule: .maxContracts, outcome: .violated, day: "2026-01-01"),
            check(rule: .preferredSession, outcome: .followed, day: "2026-01-02"),
            check(rule: .preferredSession, outcome: .followed, day: "2026-01-02"),
            check(rule: .preferredSession, outcome: .followed, day: "2026-01-02"),
            check(rule: .minPlannedRr, outcome: .violated, day: "2026-01-03"),
            check(rule: .minPlannedRr, outcome: .followed, day: "2026-01-03"),
            check(rule: .minPlannedRr, outcome: .followed, day: "2026-01-03"),
        ]
        let bundle = TradingRulesViolationPatterns.build(checks: checks, inputs: [], rulesCache: .noop)
        XCTAssertEqual(bundle.worstTradingDays.first?.dayKey, "2026-01-01")
        XCTAssertEqual(bundle.worstTradingDays.first?.violationRatePercent, 100)
    }

    func testRecurringPatternUsesEvaluatedTradingDays() {
        var checks: [TradingRulesComplianceAnalytics.Check] = []
        for day in 1 ... 7 {
            let key = String(format: "2026-01-%02d", day)
            checks.append(check(rule: .maxContracts, outcome: day <= 4 ? .violated : .followed, day: key))
            checks.append(check(rule: .preferredSession, outcome: .followed, day: key))
            checks.append(check(rule: .minPlannedRr, outcome: .followed, day: key))
        }
        let bundle = TradingRulesViolationPatterns.build(checks: checks, inputs: [], rulesCache: .noop)
        let pattern = bundle.recurringPatterns.first { $0.ruleID == .maxContracts }
        XCTAssertNotNil(pattern)
        XCTAssertEqual(pattern?.violatedDays, 4)
        XCTAssertEqual(pattern?.evaluatedDaysInWindow, 7)
        XCTAssertTrue(pattern?.summary.contains("4 of your last 7") == true)
    }

    func testViolationsForDayExcludesOtherDaysAndNonViolations() {
        let checks: [TradingRulesComplianceAnalytics.Check] = [
            check(rule: .maxContracts, outcome: .violated, day: "2026-01-05", tradeID: "a"),
            check(rule: .maxContracts, outcome: .followed, day: "2026-01-05", tradeID: "b"),
            check(rule: .maxContracts, outcome: .violated, day: "2026-01-06", tradeID: "c"),
        ]
        let events = TradingRulesViolationPatterns.violations(forDay: "2026-01-05", from: checks)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.tradeID, "a")
    }

    func testViolationPatternsBuiltWithFullAnalyticsBuild() {
        let profileID = ProfileID("patterns-integration")
        let effective = base.addingTimeInterval(-86_400)
        var global = TradingPreferenceGlobal.empty(userID: profileID)
        global.preferredSessions = ["NY AM"]
        global.maxContractsPerTrade = 1
        let revision = TradingPreferenceRevision(
            id: UUID().uuidString,
            userID: profileID,
            accountID: nil,
            effectiveFrom: effective,
            tradingStyle: nil,
            preferredSessions: ["NY AM"],
            primaryInstruments: [],
            targetRr: nil,
            maxTradesPerDay: nil,
            dailyLossLimit: nil,
            consecutiveLossPause: nil,
            breakevenTolerance: nil,
            dailyProfitTarget: nil,
            maxDrawdownGoal: nil,
            plannedStartMinute: nil,
            plannedEndMinute: nil,
            waitAfterLossMinutes: nil,
            maxRiskPerTrade: nil,
            minAcceptableRr: nil,
            allowedTradingDays: [],
            maxContractsPerTrade: 1,
            maxWeeklyLoss: nil,
            stopAfterDailyProfitTarget: false,
            maxTradesPerDayScope: .combined,
            dailyLossLimitScope: .combined,
            dailyProfitRulesScope: .combined,
            maxWeeklyLossScope: .combined,
            overridesDailyLoss: false,
            overridesDailyProfitTarget: false,
            overridesMaxDrawdownGoal: false
        )
        let context = PreferenceRuleContext(revisions: [revision], global: global, overrides: [])

        let tradeBad = Trade(
            id: TradeID("bad"),
            ownerProfileID: profileID,
            accountID: nil,
            symbol: Symbol(ticker: "ES"),
            side: .long,
            mode: .live,
            quantity: 2,
            entryPrice: 100,
            exitPrice: 99,
            entryAt: base,
            exitAt: base.addingTimeInterval(300),
            realizedPnL: Money(amount: -10),
            sessionLabel: "London",
            visibility: .private,
            createdAt: base,
            updatedAt: base
        )
        let result = TradingRulesComplianceAnalytics.build(trades: [tradeBad], context: context)
        XCTAssertGreaterThan(result.score.violated, 0)
        XCTAssertFalse(result.violationPatterns.mostBrokenRules.filter { $0.violated > 0 }.isEmpty)
        XCTAssertEqual(result.violationPatterns.ruleDrillDown[.preferredSession]?.violated, 1)
        XCTAssertEqual(result.violationPatterns.ruleDrillDown[.maxContracts]?.violated, 1)
    }

    private func check(
        rule: TradingRulesComplianceAnalytics.RuleID,
        outcome: TradingRulesComplianceAnalytics.Outcome,
        day: String,
        tradeID: String = "t1"
    ) -> TradingRulesComplianceAnalytics.Check {
        TradingRulesComplianceAnalytics.Check(
            id: "\(rule.rawValue)-\(day)-\(tradeID)-\(outcome.rawValue)",
            ruleID: rule,
            outcome: outcome,
            level: .trade,
            at: base,
            dayKey: day,
            weekKey: nil,
            monthKey: String(day.prefix(7)),
            tradeID: tradeID,
            accountID: nil,
            scopeLabel: nil,
            detail: "detail",
            pnl: nil
        )
    }
}

private extension TradingRulesResolvedRulesCache {
    static var noop: TradingRulesResolvedRulesCache {
        TradingRulesResolvedRulesCache(context: nil, inputs: [])
    }
}
