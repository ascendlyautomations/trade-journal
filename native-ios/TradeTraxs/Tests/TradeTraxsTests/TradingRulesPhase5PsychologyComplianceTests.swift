import XCTest
@testable import TradeTraxs

final class TradingRulesPhase5PsychologyComplianceTests: XCTestCase {
    private let profileID = ProfileID("phase5-psych")
    private let base = Date(timeIntervalSince1970: 1_950_000_000)

    func testConsecutiveLossPauseViolatesAtThreshold() {
        let effective = base.addingTimeInterval(-86_400)
        var global = TradingPreferenceGlobal.empty(userID: profileID)
        global.consecutiveLossPause = 2
        let context = contextWithRevision(effective: effective, global: global, pause: 2, wait: nil)

        let t0 = trade(id: "0", pnl: -10, entry: base)
        let t1 = trade(id: "1", pnl: -10, entry: base.addingTimeInterval(3600))
        let t2 = trade(id: "2", pnl: 5, entry: base.addingTimeInterval(7200))
        let result = TradingRulesComplianceAnalytics.build(trades: [t0, t1, t2], context: context)

        let pauseChecks = result.complianceChecks.filter { $0.ruleID == .consecutiveLossPause }
        XCTAssertEqual(pauseChecks.count, 3)
        XCTAssertEqual(pauseChecks.filter { $0.outcome == .violated }.map(\.tradeID), ["2"])
    }

    func testWaitAfterLossViolatedWhenRushed() {
        var global = TradingPreferenceGlobal.empty(userID: profileID)
        global.waitAfterLossMinutes = 30
        let context = contextWithRevision(effective: base.addingTimeInterval(-86_400), global: global, pause: nil, wait: 30)

        let loss = trade(id: "l", pnl: -10, entry: base, exit: base.addingTimeInterval(300))
        let rushed = trade(id: "r", pnl: 20, entry: base.addingTimeInterval(600), exit: base.addingTimeInterval(900))
        let result = TradingRulesComplianceAnalytics.build(trades: [loss, rushed], context: context)
        let waitChecks = result.complianceChecks.filter { $0.ruleID == .waitAfterLoss && $0.tradeID == "r" }
        XCTAssertEqual(waitChecks.count, 1)
        XCTAssertEqual(waitChecks.first?.outcome, .violated)
    }

    func testWaitAfterLossSkippedWhenPriorNotLoss() {
        var global = TradingPreferenceGlobal.empty(userID: profileID)
        global.waitAfterLossMinutes = 30
        let context = contextWithRevision(effective: base.addingTimeInterval(-86_400), global: global, pause: nil, wait: 30)

        let win = trade(id: "w", pnl: 10, entry: base, exit: base.addingTimeInterval(300))
        let next = trade(id: "n", pnl: 5, entry: base.addingTimeInterval(400), exit: base.addingTimeInterval(700))
        let result = TradingRulesComplianceAnalytics.build(trades: [win, next], context: context)
        let waitChecks = result.complianceChecks.filter { $0.ruleID == .waitAfterLoss && $0.tradeID == "n" }
        XCTAssertEqual(waitChecks.count, 1)
        XCTAssertEqual(waitChecks.first?.outcome, .notApplicable)
    }

    func testNoDuplicatePsychologyChecksPerTrade() {
        var global = TradingPreferenceGlobal.empty(userID: profileID)
        global.consecutiveLossPause = 1
        global.waitAfterLossMinutes = 10
        let context = contextWithRevision(effective: base.addingTimeInterval(-86_400), global: global, pause: 1, wait: 10)
        let loss = trade(id: "l", pnl: -5, entry: base, exit: base.addingTimeInterval(100))
        let next = trade(id: "n", pnl: -5, entry: base.addingTimeInterval(200), exit: base.addingTimeInterval(400))
        let result = TradingRulesComplianceAnalytics.build(trades: [loss, next], context: context)
        let grouped = Dictionary(grouping: result.complianceChecks.filter { $0.tradeID == "n" }) { $0.ruleID }
        for (_, checks) in grouped where checks.first?.ruleID == .consecutiveLossPause || checks.first?.ruleID == .waitAfterLoss {
            XCTAssertEqual(checks.count, 1)
        }
    }

    func testDisciplineDeltaWhenPriorBuildProvided() {
        let effective = base.addingTimeInterval(-86_400)
        var global = TradingPreferenceGlobal.empty(userID: profileID)
        global.preferredSessions = ["NY AM"]
        let context = contextWithRevision(effective: effective, global: global, pause: nil, wait: nil)

        let priorTrades = (0 ..< 12).map { i in
            trade(id: "p\(i)", pnl: -1, entry: base.addingTimeInterval(Double(i) * 100), session: "London")
        }
        let prior = TradingRulesComplianceAnalytics.buildDisciplinePriorMetrics(
            trades: priorTrades,
            context: context,
            psychologyContextTrades: priorTrades
        )

        let currentTrades = (0 ..< 12).map { i in
            trade(id: "c\(i)", pnl: 10, entry: base.addingTimeInterval(10_000 + Double(i) * 100), session: "NY AM")
        }
        let current = TradingRulesComplianceAnalytics.build(
            trades: currentTrades,
            context: context,
            priorDisciplineMetrics: prior
        )
        XCTAssertTrue(current.disciplineProgress.periodCompareSufficient)
        XCTAssertNotNil(current.disciplineProgress.adherenceDeltaPoints)
    }

    private func contextWithRevision(
        effective: Date,
        global: TradingPreferenceGlobal,
        pause: Int?,
        wait: Int?
    ) -> PreferenceRuleContext {
        var g = global
        g.consecutiveLossPause = pause
        g.waitAfterLossMinutes = wait
        let revision = TradingPreferenceRevision(
            id: UUID().uuidString,
            userID: profileID,
            accountID: nil,
            effectiveFrom: effective,
            tradingStyle: nil,
            preferredSessions: g.preferredSessions,
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
        return PreferenceRuleContext(revisions: [revision], global: g, overrides: [])
    }

    private func trade(
        id: String,
        pnl: Double?,
        entry: Date,
        exit: Date? = nil,
        session: String = "NY AM"
    ) -> Trade {
        Trade(
            id: TradeID(id),
            ownerProfileID: profileID,
            accountID: nil,
            symbol: Symbol(ticker: "ES"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryPrice: 100,
            exitPrice: 101,
            entryAt: entry,
            exitAt: exit ?? entry.addingTimeInterval(60),
            realizedPnL: pnl.map { Money(amount: Decimal($0)) },
            sessionLabel: session,
            visibility: .private,
            createdAt: entry,
            updatedAt: entry
        )
    }
}
