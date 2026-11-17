import XCTest
@testable import TradeTraxs

final class TradingRulesCompliancePerformanceTests: XCTestCase {
    func testRulesCacheMatchesDirectResolution() {
        let profileID = ProfileID("perf-rules-cache")
        let revision = TradingPreferenceRevision(
            id: UUID().uuidString,
            userID: profileID,
            accountID: nil,
            effectiveFrom: Date(timeIntervalSince1970: 1_700_000_000),
            tradingStyle: nil,
            preferredSessions: ["NY AM"],
            primaryInstruments: ["ES"],
            targetRr: nil,
            maxTradesPerDay: 3,
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
        var global = TradingPreferenceGlobal.empty(userID: profileID)
        global.preferredSessions = ["NY AM"]
        let context = PreferenceRuleContext(revisions: [revision], global: global, overrides: [])

        let trade = Trade(
            id: TradeID("t-perf"),
            ownerProfileID: profileID,
            accountID: nil,
            symbol: Symbol(ticker: "ES"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryPrice: 100,
            exitPrice: 101,
            entryAt: Date(timeIntervalSince1970: 1_800_000_000),
            exitAt: Date(timeIntervalSince1970: 1_800_000_300),
            realizedPnL: Money(amount: 10),
            sessionLabel: "NY AM",
            visibility: .private,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let inputs = [PreferenceComplianceEngine.input(from: trade)]
        let cache = TradingRulesResolvedRulesCache(context: context, inputs: inputs)
        let direct = PreferenceComplianceEngine.rules(
            in: context,
            at: inputs[0].at,
            accountID: inputs[0].accountID
        )
        XCTAssertEqual(cache.rules(for: inputs[0]), direct)
    }

    func testComputeProducesIdenticalScoreToSynchronousBuild() {
        let profileID = ProfileID("perf-parity")
        var global = TradingPreferenceGlobal.empty(userID: profileID)
        global.preferredSessions = ["NY AM", "London"]
        let context = PreferenceRuleContext(
            revisions: [
                TradingPreferenceRevision(
                    id: UUID().uuidString,
                    userID: profileID,
                    accountID: nil,
                    effectiveFrom: Date(timeIntervalSince1970: 1_600_000_000),
                    tradingStyle: nil,
                    preferredSessions: ["NY AM", "London"],
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
                ),
            ],
            global: global,
            overrides: []
        )

        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let trades = (0 ..< 12).map { index in
            Trade(
                id: TradeID("t-\(index)"),
                ownerProfileID: profileID,
                accountID: nil,
                symbol: Symbol(ticker: "ES"),
                side: .long,
                mode: .live,
                quantity: 1,
                entryPrice: 100,
                exitPrice: index.isMultiple(of: 2) ? 101 : 99,
                entryAt: base.addingTimeInterval(Double(index) * 3_600),
                exitAt: base.addingTimeInterval(Double(index) * 3_600 + 300),
                realizedPnL: Money(amount: index.isMultiple(of: 2) ? 25 : -10),
                sessionLabel: index.isMultiple(of: 3) ? "London" : "NY AM",
                visibility: .private,
                createdAt: base,
                updatedAt: base
            )
        }

        let baseline = TradingRulesComplianceAnalytics.build(trades: trades, context: context)
        let payload = TradingRulesComplianceCompute.computeScopedSync(
            trades: trades,
            context: context,
            dashboardInsights: nil,
            preferDashboardInsightsCache: false
        )

        XCTAssertEqual(payload.result.score.adherencePercent, baseline.score.adherencePercent)
        XCTAssertEqual(payload.result.score.followed, baseline.score.followed)
        XCTAssertEqual(payload.result.score.violated, baseline.score.violated)
        XCTAssertEqual(payload.result.score.unevaluated, baseline.score.unevaluated)
        XCTAssertEqual(payload.result.score.evaluated, baseline.score.evaluated)
        XCTAssertEqual(payload.result.weeklyTrend.count, baseline.weeklyTrend.count)
        XCTAssertEqual(payload.result.monthlyTrend.count, baseline.monthlyTrend.count)
        XCTAssertEqual(payload.result.violations.count, baseline.violations.count)
        XCTAssertEqual(
            payload.result.retrospectivelyEvaluatedTrades,
            baseline.retrospectivelyEvaluatedTrades
        )
    }
}
