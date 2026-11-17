import XCTest
@testable import TradeTraxs

final class TradingRulesP2PerformanceTests: XCTestCase {
    private let profileID = ProfileID("p2-perf")

    func testDisciplinePriorIntervalUsesEasternCalendar() {
        var scope = DashboardClientScopeFilter(
            accountFilter: .all,
            dateRange: .thirtyDays,
            customInterval: nil,
            accountMode: .all,
            showPublicOnly: false
        )
        var eastern = TradingRulesDisciplineScopeInterval.eastern
        let anchor = eastern.date(from: DateComponents(
            calendar: eastern,
            timeZone: eastern.timeZone,
            year: 2026,
            month: 3,
            day: 15,
            hour: 12
        ))!
        guard let current = TradingRulesDisciplineScopeInterval.currentInterval(scope: scope, now: anchor),
              let prior = TradingRulesDisciplineScopeInterval.priorInterval(matching: current)
        else {
            return XCTFail("Expected current and prior intervals")
        }
        XCTAssertEqual(prior.end, current.start)
        XCTAssertEqual(current.duration, prior.duration, accuracy: 1)
        XCTAssertTrue(prior.start < prior.end)
        XCTAssertTrue(prior.end <= current.start)

        scope.dateRange = .ytd
        XCTAssertNotNil(TradingRulesDisciplineScopeInterval.currentInterval(scope: scope, now: anchor))
    }

    func testPriorDisciplineMetricsMatchSubsetOfFullBuild() {
        let context = baselineContext()
        let trades = makeTrades(count: 400)
        let priorSlice = Array(trades.prefix(200))
        let currentSlice = Array(trades.suffix(200))

        let priorMetrics = TradingRulesComplianceAnalytics.buildDisciplinePriorMetrics(
            trades: priorSlice,
            context: context,
            psychologyContextTrades: priorSlice
        )
        let fullPrior = TradingRulesComplianceAnalytics.build(
            trades: priorSlice,
            context: context,
            psychologyContextTrades: priorSlice
        )

        XCTAssertEqual(priorMetrics?.score.evaluated, fullPrior.score.evaluated)
        XCTAssertEqual(priorMetrics?.score.followed, fullPrior.score.followed)
        XCTAssertEqual(priorMetrics?.score.violated, fullPrior.score.violated)

        let current = TradingRulesComplianceAnalytics.build(
            trades: currentSlice,
            context: context,
            priorDisciplineMetrics: priorMetrics
        )
        XCTAssertTrue(current.disciplineProgress.periodCompareSufficient || current.disciplineProgress.insufficientData)
    }

    func testBuildPerformance10kTradesRemainsUnderBudget() {
        let context = baselineContext()
        let trades = makeTrades(count: 10_000)
        measure {
            let result = TradingRulesComplianceAnalytics.build(trades: trades, context: context)
            XCTAssertGreaterThan(result.score.evaluated, 0)
        }
    }

    func testDisciplinePriorMetricsCheaperThanFullBuild() {
        let context = baselineContext()
        let priorTrades = makeTrades(count: 1_500)

        let priorOnlyStart = CFAbsoluteTimeGetCurrent()
        let metrics = TradingRulesComplianceAnalytics.buildDisciplinePriorMetrics(
            trades: priorTrades,
            context: context,
            psychologyContextTrades: priorTrades
        )
        let priorOnlyMs = (CFAbsoluteTimeGetCurrent() - priorOnlyStart) * 1000

        let fullStart = CFAbsoluteTimeGetCurrent()
        let full = TradingRulesComplianceAnalytics.build(trades: priorTrades, context: context)
        let fullMs = (CFAbsoluteTimeGetCurrent() - fullStart) * 1000

        XCTAssertNotNil(metrics)
        XCTAssertEqual(metrics?.score.evaluated, full.score.evaluated)
        XCTAssertLessThan(priorOnlyMs, fullMs * 0.9, "Prior discipline path should skip impact/trends/patterns")
    }

    func testImpactSamplesCappedPerSide() {
        let context = baselineContext()
        var global = TradingPreferenceGlobal.empty(userID: profileID)
        global.maxContractsPerTrade = 2
        let richContext = PreferenceRuleContext(
            revisions: [revision(global: global, sessions: [])],
            global: global,
            overrides: []
        )
        let trades = makeTrades(count: 80)
        let result = TradingRulesComplianceAnalytics.build(trades: trades, context: richContext)
        for row in result.impacts {
            XCTAssertLessThanOrEqual(row.followed.tradeSamples.count, TradingRulesRuleImpact.maxTradeSamplesPerSide)
            XCTAssertLessThanOrEqual(row.violated.tradeSamples.count, TradingRulesRuleImpact.maxTradeSamplesPerSide)
        }
    }

    // MARK: - Fixtures

    private func baselineContext() -> PreferenceRuleContext {
        var global = TradingPreferenceGlobal.empty(userID: profileID)
        global.preferredSessions = ["NY AM", "London"]
        global.maxTradesPerDay = 5
        return PreferenceRuleContext(revisions: [revision(global: global, sessions: ["NY AM", "London"])], global: global, overrides: [])
    }

    private func revision(global: TradingPreferenceGlobal, sessions: [String]) -> TradingPreferenceRevision {
        TradingPreferenceRevision(
            id: UUID().uuidString,
            userID: profileID,
            accountID: nil,
            effectiveFrom: Date(timeIntervalSince1970: 1_600_000_000),
            tradingStyle: nil,
            preferredSessions: sessions,
            primaryInstruments: [],
            targetRr: nil,
            maxTradesPerDay: global.maxTradesPerDay,
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
            maxContractsPerTrade: global.maxContractsPerTrade,
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

    private func makeTrades(count: Int) -> [Trade] {
        let base = Date(timeIntervalSince1970: 1_900_000_000)
        let account = TradingAccountID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        var trades: [Trade] = []
        trades.reserveCapacity(count)
        for index in 0 ..< count {
            let win = index.isMultiple(of: 2)
            let pnl = Money(amount: win ? 25 : -10)
            let entry = base.addingTimeInterval(Double(index) * 90)
            trades.append(
                Trade(
                    id: TradeID("p2-\(index)"),
                    ownerProfileID: profileID,
                    accountID: index.isMultiple(of: 2) ? account : nil,
                    symbol: Symbol(ticker: index.isMultiple(of: 3) ? "NQ" : "ES"),
                    side: .long,
                    mode: .live,
                    quantity: Decimal(1 + (index % 5)),
                    entryPrice: 100,
                    exitPrice: win ? 101 : 99,
                    entryAt: entry,
                    exitAt: entry.addingTimeInterval(60),
                    realizedPnL: pnl,
                    sessionLabel: index.isMultiple(of: 4) ? "London" : "NY AM",
                    visibility: .private,
                    createdAt: base,
                    updatedAt: base
                )
            )
        }
        return trades
    }
}
