import XCTest
@testable import TradeTraxs

final class TradingRulesP0CorrectnessTests: XCTestCase {
    private let profileID = ProfileID("p0-rules")
    private let accountA = TradingAccountID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private let accountB = TradingAccountID("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
    private let base = Date(timeIntervalSince1970: 1_960_000_000)

    func testDashboardAndAnalyticsParityForPsychologyStreak() {
        let effective = base.addingTimeInterval(-86_400)
        let context = contextWithPause(effective: effective, pause: 2)

        let lossA1 = trade(id: "l1", account: accountA, pnl: -10, entry: base)
        let lossA2 = trade(id: "l2", account: accountA, pnl: -10, entry: base.addingTimeInterval(60))
        let breach = trade(id: "b", account: accountA, pnl: 5, entry: base.addingTimeInterval(120))

        let scoped = [lossA1, lossA2, breach]
        let psychologyHistory = scoped
        let inputs = scoped.map(PreferenceComplianceEngine.input(from:)).sorted { $0.at < $1.at }
        let rulesCache = TradingRulesResolvedRulesCache(context: context, inputs: inputs)

        let dashboardResult = TradingRulesComplianceAnalytics.build(
            inputs: inputs,
            context: context,
            rulesCache: rulesCache,
            trades: scoped,
            psychologyContextTrades: psychologyHistory
        )

        let fullResult = TradingRulesComplianceAnalytics.build(
            trades: scoped,
            context: context,
            psychologyContextTrades: psychologyHistory
        )

        let dashPause = dashboardResult.complianceChecks.filter { $0.ruleID == .consecutiveLossPause && $0.tradeID == "b" }
        let fullPause = fullResult.complianceChecks.filter { $0.ruleID == .consecutiveLossPause && $0.tradeID == "b" }
        XCTAssertEqual(dashPause.first?.outcome, fullPause.first?.outcome)
        XCTAssertEqual(dashPause.first?.outcome, .violated)
    }

    func testConsecutiveLossStreakIsolatedPerAccount() {
        let context = contextWithPause(effective: base.addingTimeInterval(-86_400), pause: 2)
        let lossA = trade(id: "l1", account: accountA, pnl: -10, entry: base)
        let lossB = trade(id: "l2", account: accountB, pnl: -10, entry: base.addingTimeInterval(60))
        let entryA = trade(id: "b", account: accountA, pnl: 5, entry: base.addingTimeInterval(120))
        let result = TradingRulesComplianceAnalytics.build(trades: [lossA, lossB, entryA], context: context)
        let check = result.complianceChecks.first { $0.tradeID == "b" && $0.ruleID == .consecutiveLossPause }
        XCTAssertEqual(check?.outcome, .followed)
    }

    func testRequiresCompleteHistoryWhenPsychologyRulesConfigured() {
        var global = TradingPreferenceGlobal.empty(userID: profileID)
        global.waitAfterLossMinutes = 15
        let context = PreferenceRuleContext(revisions: [], global: global, overrides: [])
        XCTAssertTrue(
            TradingRulesComplianceDisciplineContextBuilder.requiresCompleteHistoryForPsychology(context: context)
        )
    }

    func testDisciplineBuilderMatchesScopedAndFullPsychologyHistory() async {
        let effective = base.addingTimeInterval(-86_400)
        let context = contextWithWait(effective: effective, wait: 30)
        let priorLoss = trade(
            id: "prior",
            account: accountA,
            pnl: -5,
            entry: base.addingTimeInterval(-86_400 * 5),
            exit: base.addingTimeInterval(-86_400 * 5 + 100)
        )
        let inScope = trade(id: "in", account: accountA, pnl: 10, entry: base)
        let owner = [priorLoss, inScope]
        let scope = DashboardClientScopeFilter(
            accountFilter: .all,
            dateRange: .thirtyDays,
            customInterval: DateInterval(start: base.addingTimeInterval(-86_400 * 10), end: base.addingTimeInterval(86_400)),
            accountMode: .all,
            showPublicOnly: false
        )

        let prepared = TradingRulesComplianceDisciplineContextBuilder.prepare(
            ownerTrades: owner,
            accounts: [],
            scopeFilter: scope,
            preferences: context,
            historyComplete: true
        )
        XCTAssertFalse(prepared.psychologyContextTrades.isEmpty)
        XCTAssertTrue(prepared.psychologyContextTrades.contains { $0.id.rawValue == "prior" })

        let scopedPayload = TradingRulesComplianceCompute.computeScopedSync(
            trades: [inScope],
            context: context,
            dashboardInsights: nil,
            preferDashboardInsightsCache: false,
            discipline: prepared.discipline
        )
        let resolvedScope = PsychologyAnalyticsScopeResolver.resolve(filter: scope, profileID: profileID)
        let coldPayload = await TradingRulesComplianceSnapshotBuilder.buildFromScopedTrades(
            trades: [inScope],
            scope: resolvedScope,
            preferences: context,
            accounts: [],
            ownerTrades: owner,
            historyComplete: true
        )
        let waitRule = TradingRulesComplianceAnalytics.RuleID.waitAfterLoss
        let scopedWait: [TradingRulesComplianceAnalytics.Outcome] = scopedPayload.result.complianceChecks
            .filter { $0.ruleID == waitRule }
            .map(\.outcome)
        let coldWait: [TradingRulesComplianceAnalytics.Outcome] = coldPayload.result?.complianceChecks
            .filter { $0.ruleID == waitRule }
            .map(\.outcome) ?? []
        XCTAssertEqual(scopedWait, coldWait)
    }

    func testWaitAfterLossUsesSameAccountOnly() {
        let context = contextWithWait(effective: base.addingTimeInterval(-86_400), wait: 30)
        let lossA = trade(id: "l", account: accountA, pnl: -5, entry: base, exit: base.addingTimeInterval(100))
        let rushB = trade(id: "r", account: accountB, pnl: 10, entry: base.addingTimeInterval(110))
        let okA = trade(id: "ok", account: accountA, pnl: 1, entry: base.addingTimeInterval(400))
        let ordered = [lossA, rushB, okA]
        var state = TradingRulesComplianceAnalytics.BuildState()
        TradingRulesPsychologyCompliance.evaluate(
            contextTrades: ordered,
            scopedTradeIDs: Set(ordered.map(\.id.rawValue)),
            context: context,
            state: &state
        )
        let waitChecks = state.checks.filter { $0.ruleID == .waitAfterLoss && $0.tradeID == "ok" }
        XCTAssertEqual(waitChecks.count, 1)
        XCTAssertEqual(waitChecks.first?.outcome, .violated)
        XCTAssertFalse(state.checks.contains { $0.ruleID == .waitAfterLoss && $0.tradeID == "r" && $0.outcome == .violated })
    }

    func testPsychologyFingerprintChangesWhenOutOfScopeTradeUpdates() {
        let inScope = trade(id: "in", account: accountA, pnl: 10, entry: base)
        let outOfScope = trade(id: "out", account: accountA, pnl: -5, entry: base.addingTimeInterval(-86_400 * 30))
        let fp1 = TradingRulesComplianceInputFingerprint.make(
            scopeFingerprint: "scope",
            preferencesFingerprint: "prefs",
            trades: [inScope],
            psychologyHistoryTrades: [inScope, outOfScope],
            ownerHistoryComplete: true,
            preferCachedInsights: false
        )
        var edited = outOfScope
        edited.updatedAt = base.addingTimeInterval(3600)
        let fp2 = TradingRulesComplianceInputFingerprint.make(
            scopeFingerprint: "scope",
            preferencesFingerprint: "prefs",
            trades: [inScope],
            psychologyHistoryTrades: [inScope, edited],
            ownerHistoryComplete: true,
            preferCachedInsights: false
        )
        XCTAssertNotEqual(fp1, fp2)
    }

    func testConsecutivePauseNotPermanentAfterWin() {
        let context = contextWithPause(effective: base.addingTimeInterval(-86_400), pause: 2)
        let t0 = trade(id: "0", account: accountA, pnl: -1, entry: base)
        let t1 = trade(id: "1", account: accountA, pnl: -1, entry: base.addingTimeInterval(60))
        let t2 = trade(id: "2", account: accountA, pnl: 10, entry: base.addingTimeInterval(120))
        let t3 = trade(id: "3", account: accountA, pnl: -1, entry: base.addingTimeInterval(180))
        let result = TradingRulesComplianceAnalytics.build(trades: [t0, t1, t2, t3], context: context)
        let t3check = result.complianceChecks.first { $0.tradeID == "3" && $0.ruleID == .consecutiveLossPause }
        XCTAssertEqual(t3check?.outcome, .followed)
    }

    private func contextWithPause(effective: Date, pause: Int) -> PreferenceRuleContext {
        var global = TradingPreferenceGlobal.empty(userID: profileID)
        global.consecutiveLossPause = pause
        return revisionContext(effective: effective, global: global, pause: pause, wait: nil)
    }

    private func contextWithWait(effective: Date, wait: Int) -> PreferenceRuleContext {
        var global = TradingPreferenceGlobal.empty(userID: profileID)
        global.waitAfterLossMinutes = wait
        return revisionContext(effective: effective, global: global, pause: nil, wait: wait)
    }

    private func revisionContext(
        effective: Date,
        global: TradingPreferenceGlobal,
        pause: Int?,
        wait: Int?
    ) -> PreferenceRuleContext {
        let revision = TradingPreferenceRevision(
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
        return PreferenceRuleContext(revisions: [revision], global: global, overrides: [])
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
