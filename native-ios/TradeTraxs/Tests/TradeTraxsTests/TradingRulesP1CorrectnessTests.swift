import XCTest
@testable import TradeTraxs

final class TradingRulesP1CorrectnessTests: XCTestCase {
    private let profileID = ProfileID("p1-rules")
    private let accountA = TradingAccountID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private let accountB = TradingAccountID("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
    private let base = Date(timeIntervalSince1970: 1_970_000_000)

    // MARK: - Psychology outcomes

    func testWaitUnevaluatedWhenPriorLossMissingExit() {
        let context = contextWithWait(wait: 30)
        var loss = trade(id: "l", account: accountA, pnl: -10, entry: base)
        loss.exitAt = nil
        let next = trade(id: "n", account: accountA, pnl: 5, entry: base.addingTimeInterval(3600))
        let result = TradingRulesComplianceAnalytics.build(trades: [loss, next], context: context)
        let check = result.complianceChecks.first { $0.ruleID == .waitAfterLoss && $0.tradeID == "n" }
        XCTAssertEqual(check?.outcome, .unevaluated)
        XCTAssertEqual(result.score.violated, 0)
        XCTAssertGreaterThanOrEqual(result.score.unevaluated, 1)
    }

    func testWaitUnevaluatedWhenEntryOverlapsPriorExit() {
        let context = contextWithWait(wait: 30)
        let lossExit = base.addingTimeInterval(600)
        let loss = trade(id: "l", account: accountA, pnl: -10, entry: base, exit: lossExit)
        let overlap = trade(id: "o", account: accountA, pnl: 1, entry: base.addingTimeInterval(500))
        let result = TradingRulesComplianceAnalytics.build(trades: [loss, overlap], context: context)
        let check = result.complianceChecks.first { $0.tradeID == "o" && $0.ruleID == .waitAfterLoss }
        XCTAssertEqual(check?.outcome, .unevaluated)
    }

    func testWaitUsesExitNotEntryGap() {
        let context = contextWithWait(wait: 30)
        let loss = trade(id: "l", account: accountA, pnl: -10, entry: base, exit: base.addingTimeInterval(100))
        let ok = trade(id: "ok", account: accountA, pnl: 5, entry: base.addingTimeInterval(4000))
        let result = TradingRulesComplianceAnalytics.build(trades: [loss, ok], context: context)
        let check = result.complianceChecks.first { $0.tradeID == "ok" }
        XCTAssertEqual(check?.outcome, .followed)
    }

    func testWaitNotApplicableAfterWinOnSameAccount() {
        let context = contextWithWait(wait: 30)
        let win = trade(id: "w", account: accountA, pnl: 10, entry: base, exit: base.addingTimeInterval(100))
        let next = trade(id: "n", account: accountA, pnl: 5, entry: base.addingTimeInterval(400))
        let result = TradingRulesComplianceAnalytics.build(trades: [win, next], context: context)
        let check = result.complianceChecks.first { $0.ruleID == .waitAfterLoss && $0.tradeID == "n" }
        XCTAssertEqual(check?.outcome, .notApplicable)
        XCTAssertEqual(result.score.evaluated, 0)
    }

    func testPauseDoesNotCountUnpricedTradeInStreak() {
        let context = contextWithPause(pause: 2)
        let loss1 = trade(id: "1", account: accountA, pnl: -5, entry: base)
        let unpriced = trade(id: "u", account: accountA, pnl: nil, entry: base.addingTimeInterval(60))
        let entry = trade(id: "e", account: accountA, pnl: 1, entry: base.addingTimeInterval(120))
        let result = TradingRulesComplianceAnalytics.build(trades: [loss1, unpriced, entry], context: context)
        let check = result.complianceChecks.first { $0.tradeID == "e" && $0.ruleID == .consecutiveLossPause }
        XCTAssertEqual(check?.outcome, .followed)
    }

    func testPauseResetsAcrossTradingDaysButStaysUntilWin() {
        let context = contextWithPause(pause: 2)
        let day1Loss = trade(id: "d1", account: accountA, pnl: -1, entry: base)
        let day2Loss = trade(
            id: "d2",
            account: accountA,
            pnl: -1,
            entry: base.addingTimeInterval(86_400 * 2)
        )
        let day3Entry = trade(
            id: "d3",
            account: accountA,
            pnl: 5,
            entry: base.addingTimeInterval(86_400 * 3)
        )
        let result = TradingRulesComplianceAnalytics.build(trades: [day1Loss, day2Loss, day3Entry], context: context)
        let check = result.complianceChecks.first { $0.tradeID == "d3" && $0.ruleID == .consecutiveLossPause }
        XCTAssertEqual(check?.outcome, .violated)
        let winReset = trade(
            id: "w",
            account: accountA,
            pnl: 10,
            entry: base.addingTimeInterval(86_400 * 4)
        )
        let afterWin = trade(
            id: "a",
            account: accountA,
            pnl: -1,
            entry: base.addingTimeInterval(86_400 * 5)
        )
        let result2 = TradingRulesComplianceAnalytics.build(
            trades: [day1Loss, day2Loss, day3Entry, winReset, afterWin],
            context: context
        )
        let afterWinCheck = result2.complianceChecks.first { $0.tradeID == "a" && $0.ruleID == .consecutiveLossPause }
        XCTAssertEqual(afterWinCheck?.outcome, .followed)
    }

    func testNotApplicableExcludedFromAdherenceDenominator() {
        let context = contextWithWait(wait: 15)
        let win = trade(id: "w", account: accountA, pnl: 1, entry: base)
        let result = TradingRulesComplianceAnalytics.build(trades: [win], context: context)
        XCTAssertEqual(result.score.evaluated, 0)
        XCTAssertEqual(result.score.followed, 0)
        XCTAssertEqual(result.score.violated, 0)
    }

    func testHistoricalRevisionChangesPauseThreshold() {
        var global = TradingPreferenceGlobal.empty(userID: profileID)
        global.consecutiveLossPause = 3
        let earlyRevision = revision(effective: base.addingTimeInterval(-86_400 * 10), pause: 3, wait: nil)
        let lateRevision = revision(effective: base.addingTimeInterval(-86_400), pause: 1, wait: nil)
        let context = PreferenceRuleContext(revisions: [earlyRevision, lateRevision], global: global, overrides: [])

        let loss = trade(id: "l", account: accountA, pnl: -1, entry: base.addingTimeInterval(-3600))
        let scoped = trade(id: "s", account: accountA, pnl: 1, entry: base)
        let result = TradingRulesComplianceAnalytics.build(trades: [loss, scoped], context: context)
        let check = result.complianceChecks.first { $0.tradeID == "s" && $0.ruleID == .consecutiveLossPause }
        XCTAssertEqual(check?.outcome, .violated)
    }

    func testDailyLossImpactExcludesDayLevelChecks() {
        var global = TradingPreferenceGlobal.empty(userID: profileID)
        global.dailyLossLimit = 50
        var limitRevision = revision(effective: base.addingTimeInterval(-86_400), pause: nil, wait: nil)
        limitRevision.dailyLossLimit = 50
        let context = PreferenceRuleContext(
            revisions: [limitRevision],
            global: global,
            overrides: []
        )
        let t1 = trade(id: "1", account: accountA, pnl: -60, entry: base)
        let result = TradingRulesComplianceAnalytics.build(trades: [t1], context: context)
        let dayChecks = result.complianceChecks.filter { $0.ruleID == .dailyLossLimit }
        XCTAssertFalse(dayChecks.isEmpty)
        XCTAssertTrue(dayChecks.contains { $0.level == .day })
        let impact = result.impacts.first { $0.ruleID == .dailyLossLimit }
        XCTAssertNil(impact, "Day/week-only checks must not produce trade-level rule impact rows.")
    }

    func testScoreFormulaUnchangedWithUnevaluatedPsychology() {
        let context = contextWithWait(wait: 30)
        var loss = trade(id: "l", account: accountA, pnl: -5, entry: base)
        loss.exitAt = nil
        let next = trade(id: "n", account: accountA, pnl: 2, entry: base.addingTimeInterval(7200))
        let result = TradingRulesComplianceAnalytics.build(trades: [loss, next], context: context)
        let f = result.score.followed
        let v = result.score.violated
        let evaluated = result.score.evaluated
        XCTAssertEqual(evaluated, f + v)
        if evaluated > 0, let pct = result.score.adherencePercent {
            XCTAssertEqual(pct, round((Double(f) / Double(evaluated)) * 1000) / 10)
        }
    }

    // MARK: - Helpers

    private func contextWithPause(pause: Int) -> PreferenceRuleContext {
        var global = TradingPreferenceGlobal.empty(userID: profileID)
        global.consecutiveLossPause = pause
        return PreferenceRuleContext(
            revisions: [revision(effective: base.addingTimeInterval(-86_400), pause: pause, wait: nil)],
            global: global,
            overrides: []
        )
    }

    private func contextWithWait(wait: Int) -> PreferenceRuleContext {
        var global = TradingPreferenceGlobal.empty(userID: profileID)
        global.waitAfterLossMinutes = wait
        return PreferenceRuleContext(
            revisions: [revision(effective: base.addingTimeInterval(-86_400), pause: nil, wait: wait)],
            global: global,
            overrides: []
        )
    }

    private func revision(effective: Date, pause: Int?, wait: Int?) -> TradingPreferenceRevision {
        TradingPreferenceRevision(
            id: UUID().uuidString,
            userID: profileID,
            accountID: nil,
            effectiveFrom: effective,
            tradingStyle: nil,
            preferredSessions: [],
            primaryInstruments: [],
            targetRr: nil,
            maxTradesPerDay: nil,
            dailyLossLimit: nil,
            consecutiveLossPause: pause,
            breakevenTolerance: nil,
            dailyProfitTarget: nil,
            maxDrawdownGoal: nil,
            plannedStartMinute: nil,
            plannedEndMinute: nil,
            waitAfterLossMinutes: wait,
            maxRiskPerTrade: nil,
            minAcceptableRr: nil,
            allowedTradingDays: [],
            maxContractsPerTrade: nil,
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
    }

    private func trade(
        id: String,
        account: TradingAccountID,
        pnl: Double?,
        entry: Date,
        exit: Date? = nil
    ) -> Trade {
        Trade(
            id: TradeID(id),
            ownerProfileID: profileID,
            accountID: account,
            symbol: Symbol(ticker: "ES"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryPrice: 100,
            exitPrice: 101,
            entryAt: entry,
            exitAt: exit ?? entry.addingTimeInterval(60),
            realizedPnL: pnl.map { Money(amount: Decimal($0)) },
            sessionLabel: "NY AM",
            visibility: .private,
            createdAt: entry,
            updatedAt: entry
        )
    }
}
