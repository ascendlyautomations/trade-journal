import XCTest
@testable import TradeTraxs

final class TradingRulesRuleImpactTests: XCTestCase {
    private let profileID = ProfileID("impact-tests")
    private let base = Date(timeIntervalSince1970: 1_900_000_000)

    func testNetPnlUsesRealizedPnl() {
        let trade = pricedTrade(id: "t1", pnl: 100)
        XCTAssertEqual(TradingRulesRuleImpact.netPnl(for: trade), 100)
        XCTAssertNil(TradingRulesRuleImpact.netPnl(for: pricedTrade(id: "t2", pnl: nil)))
    }

    func testProfitFactorUndefinedWhenNoGrossLosses() {
        var side = TradingRulesComplianceAnalytics.ImpactSide()
        side.priced = 2
        side.wins = 2
        side.grossWins = 80
        side.totalNetPnl = 80
        side.finalizeMetrics()
        XCTAssertNil(side.profitFactor)
    }

    func testProfitFactorExpectancyAndWinRate() {
        var side = TradingRulesComplianceAnalytics.ImpactSide()
        side.priced = 3
        side.wins = 2
        side.losses = 1
        side.breakeven = 0
        side.grossWins = 100
        side.grossLosses = -25
        side.totalNetPnl = 75
        side.finalizeMetrics()
        XCTAssertEqual(side.profitFactor!, 100 / 25, accuracy: 0.01)
        XCTAssertEqual(side.winRateFraction!, 2.0 / 3.0, accuracy: 0.01)
        XCTAssertNotNil(side.expectancy)
    }

    func testBreakevenCountsAsPricedNotWin() {
        var side = TradingRulesComplianceAnalytics.ImpactSide()
        side.priced = 2
        side.wins = 1
        side.breakeven = 1
        side.grossWins = 10
        side.totalNetPnl = 10
        side.finalizeMetrics()
        XCTAssertEqual(side.winRateFraction!, 0.5, accuracy: 0.01)
    }

    func testNoDoubleCountPerRuleAndOutcome() {
        let trade = pricedTrade(id: "dup", pnl: -20)
        let tradeMap = [trade.id.rawValue: trade]
        let checks = [
            tradeCheck(rule: .maxContracts, outcome: .violated, tradeID: "dup"),
            tradeCheck(rule: .maxContracts, outcome: .violated, tradeID: "dup"),
        ]
        let rows = TradingRulesRuleImpact.buildImpactRows(checks: checks, tradesByID: tradeMap)
        let row = rows.first { $0.ruleID == .maxContracts }
        XCTAssertEqual(row?.violated.priced, 1)
        XCTAssertEqual(row?.violated.totalNetPnl, -20)
    }

    func testDayLevelChecksExcludedFromImpact() {
        let trade = pricedTrade(id: "day", pnl: -50)
        let tradeMap = [trade.id.rawValue: trade]
        let checks = [
            TradingRulesComplianceAnalytics.Check(
                id: "c1",
                ruleID: .dailyLossLimit,
                outcome: .violated,
                level: .day,
                at: base,
                dayKey: "2026-02-01",
                weekKey: nil,
                monthKey: "2026-02",
                tradeID: trade.id.rawValue,
                accountID: nil,
                scopeLabel: nil,
                detail: "day breach",
                pnl: -50
            ),
        ]
        let rows = TradingRulesRuleImpact.buildImpactRows(checks: checks, tradesByID: tradeMap)
        XCTAssertTrue(rows.isEmpty)
    }

    func testHighlightsRequireSufficientSampleOnBothSides() {
        var followed = TradingRulesComplianceAnalytics.ImpactSide()
        followed.priced = 6
        followed.avgNetPnl = 10
        followed.winRateFraction = 0.6
        var violated = TradingRulesComplianceAnalytics.ImpactSide()
        violated.priced = 6
        violated.avgNetPnl = -5
        violated.winRateFraction = 0.3
        let row = TradingRulesComplianceAnalytics.ImpactRow(
            ruleID: .preferredSession,
            ruleLabel: "Preferred session",
            followed: followed,
            violated: violated,
            sufficientSample: true,
            summary: nil,
            avgPnlDelta: 15,
            winRateDeltaPoints: 30
        )
        let highlights = TradingRulesRuleImpact.comparisonHighlights(from: [row])
        XCTAssertEqual(highlights.count, 1)
        XCTAssertEqual(highlights.first?.avgPnlDelta, 15)
    }

    func testIntegrationBuildProducesImpactHighlights() {
        let effective = base.addingTimeInterval(-86_400)
        var global = TradingPreferenceGlobal.empty(userID: profileID)
        global.preferredSessions = ["NY AM"]
        let revision = minimalRevision(effectiveFrom: effective, sessions: ["NY AM"])
        let context = PreferenceRuleContext(revisions: [revision], global: global, overrides: [])

        var trades: [Trade] = []
        for i in 0 ..< 12 {
            let good = i % 2 == 0
            trades.append(
                pricedTrade(
                    id: "t\(i)",
                    pnl: good ? 40 : -15,
                    session: good ? "NY AM" : "London",
                    at: base.addingTimeInterval(Double(i) * 3600)
                )
            )
        }
        let result = TradingRulesComplianceAnalytics.build(trades: trades, context: context)
        XCTAssertFalse(result.impacts.isEmpty)
        let sessionImpact = result.impacts.first { $0.ruleID == .preferredSession }
        XCTAssertNotNil(sessionImpact)
        XCTAssertGreaterThan(sessionImpact!.followed.priced + sessionImpact!.violated.priced, 0)
    }

    private func tradeCheck(
        rule: TradingRulesComplianceAnalytics.RuleID,
        outcome: TradingRulesComplianceAnalytics.Outcome,
        tradeID: String
    ) -> TradingRulesComplianceAnalytics.Check {
        TradingRulesComplianceAnalytics.Check(
            id: UUID().uuidString,
            ruleID: rule,
            outcome: outcome,
            level: .trade,
            at: base,
            dayKey: "2026-01-01",
            weekKey: nil,
            monthKey: "2026-01",
            tradeID: tradeID,
            accountID: nil,
            scopeLabel: nil,
            detail: "",
            pnl: nil
        )
    }

    private func pricedTrade(
        id: String,
        pnl: Double?,
        session: String = "NY AM",
        at: Date? = nil
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
            entryAt: at ?? base,
            exitAt: (at ?? base).addingTimeInterval(300),
            realizedPnL: pnl.map { Money(amount: Decimal($0)) },
            sessionLabel: session,
            visibility: .private,
            createdAt: at ?? base,
            updatedAt: at ?? base
        )
    }

    private func minimalRevision(effectiveFrom: Date, sessions: [String]) -> TradingPreferenceRevision {
        TradingPreferenceRevision(
            id: UUID().uuidString,
            userID: profileID,
            accountID: nil,
            effectiveFrom: effectiveFrom,
            tradingStyle: nil,
            preferredSessions: sessions,
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
}
