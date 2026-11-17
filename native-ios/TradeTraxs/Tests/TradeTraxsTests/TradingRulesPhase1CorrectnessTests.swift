import XCTest
@testable import TradeTraxs

final class TradingRulesPhase1CorrectnessTests: XCTestCase {
    private let profileID = ProfileID("rules-phase1-user")
    private let accountID = TradingAccountID("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")

    private var firstSave: Date!
    private var beforeFirstSave: Date!
    private var afterFirstSave: Date!

    override func setUp() {
        super.setUp()
        firstSave = Date(timeIntervalSince1970: 1_700_000_000)
        beforeFirstSave = firstSave.addingTimeInterval(-86_400)
        afterFirstSave = firstSave.addingTimeInterval(86_400)
    }

    // MARK: - Revision / retrospective

    func testRulesWithEmptyRevisionsNeverAppliesLiveGlobals() {
        let context = preferenceContext(
            revisions: [],
            global: globalWithSessions(["NY AM"]),
            applyPast: true
        )
        let rules = PreferenceComplianceEngine.rules(in: context, at: afterFirstSave, accountID: nil)
        XCTAssertFalse(rules.hasActiveRuleChecks)
    }

    func testRetrospectiveOnlyBeforeFirstGlobalRevisionWhenEnabled() {
        let revision = globalRevision(effectiveFrom: firstSave, sessions: ["London"])
        let context = preferenceContext(
            revisions: [revision],
            global: globalWithSessions(["NY AM"]),
            applyPast: true
        )

        let beforeRules = PreferenceComplianceEngine.rules(in: context, at: beforeFirstSave, accountID: nil)
        XCTAssertTrue(beforeRules.preferredSessions.contains("NY AM"))

        let afterRules = PreferenceComplianceEngine.rules(in: context, at: afterFirstSave, accountID: nil)
        XCTAssertEqual(afterRules.preferredSessions, ["London"])
    }

    func testRetrospectiveDisabledBeforeFirstRevisionLeavesRulesInactive() {
        let revision = globalRevision(effectiveFrom: firstSave, sessions: ["London"])
        let context = preferenceContext(
            revisions: [revision],
            global: globalWithSessions(["NY AM"]),
            applyPast: false
        )

        let beforeRules = PreferenceComplianceEngine.rules(in: context, at: beforeFirstSave, accountID: nil)
        XCTAssertFalse(beforeRules.hasActiveRuleChecks)
        XCTAssertFalse(
            PreferenceComplianceEngine.usesRetrospectiveRuleApplication(
                in: context,
                at: beforeFirstSave,
                accountID: nil
            )
        )
    }

    func testAfterFirstRevisionNeverAppliesCurrentRulesToEmptyHistoricalGap() {
        let revision = globalRevision(effectiveFrom: firstSave, sessions: ["London"])
        let context = preferenceContext(
            revisions: [revision],
            global: globalWithSessions(["NY AM"]),
            applyPast: true
        )
        let rules = PreferenceComplianceEngine.rules(in: context, at: afterFirstSave, accountID: nil)
        XCTAssertEqual(rules.preferredSessions, ["London"])
        XCTAssertFalse(
            PreferenceComplianceEngine.usesRetrospectiveRuleApplication(
                in: context,
                at: afterFirstSave,
                accountID: nil
            )
        )
    }

    func testFirstGlobalRuleEffectiveAtUsesEarliestRevision() {
        let later = globalRevision(effectiveFrom: firstSave.addingTimeInterval(10_000), sessions: ["NY PM"])
        let earlier = globalRevision(effectiveFrom: firstSave, sessions: ["NY AM"])
        let context = preferenceContext(
            revisions: [later, earlier],
            global: globalWithSessions(["NY AM"]),
            applyPast: false
        )
        XCTAssertEqual(
            PreferenceComplianceEngine.firstGlobalRuleEffectiveAt(in: context),
            firstSave
        )
    }

    // MARK: - Configured rule detection

    func testProfitStopRequiresStopAfterFlag() {
        var resolved = ResolvedTradingPreferences.empty
        resolved.dailyProfitTarget = 500
        resolved.stopAfterDailyProfitTarget = false
        XCTAssertFalse(resolved.hasActiveRuleChecks)

        resolved.stopAfterDailyProfitTarget = true
        XCTAssertTrue(resolved.hasActiveRuleChecks)
    }

    func testDiagnosticsCountProfitStopOnlyWhenStopEnabled() {
        let global = globalWithSessions(["NY AM"])
        var withTargetOnly = global
        withTargetOnly.dailyProfitTarget = 1_000
        withTargetOnly.stopAfterDailyProfitTarget = false
        let contextTargetOnly = preferenceContext(revisions: [], global: withTargetOnly, applyPast: false)
        XCTAssertEqual(TradingRulesComplianceDiagnostics.configuredRuleFamilyCount(context: contextTargetOnly), 1)

        var withStop = global
        withStop.dailyProfitTarget = 1_000
        withStop.stopAfterDailyProfitTarget = true
        let contextStop = preferenceContext(revisions: [], global: withStop, applyPast: false)
        XCTAssertEqual(TradingRulesComplianceDiagnostics.configuredRuleFamilyCount(context: contextStop), 2)
    }

    // MARK: - Trends

    func testTrendPeriodWithFewerThanThreeEvaluatedChecksMarksInsufficientData() {
        let revision = globalRevision(effectiveFrom: firstSave, sessions: ["NY AM"])
        let context = preferenceContext(
            revisions: [revision],
            global: globalWithSessions(["NY AM"]),
            applyPast: false
        )
        let trades = [
            makeTrade(id: "t1", entryAt: afterFirstSave, session: "NY AM"),
            makeTrade(id: "t2", entryAt: afterFirstSave.addingTimeInterval(60), session: "NY AM"),
        ]
        let result = TradingRulesComplianceAnalytics.build(trades: trades, context: context)
        let weekly = result.weeklyTrend
        XCTAssertFalse(weekly.isEmpty)
        XCTAssertTrue(weekly.contains(where: { $0.insufficientData && $0.adherencePercent == nil }))
    }

    // MARK: - Eastern week

    func testEasternWeekKeyMatchesMondayStartForWednesdayTrade() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let wednesday = calendar.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 10))!
        let dayKey = TradingSessionLabel.easternTradeDateString(from: wednesday)
        XCTAssertEqual(dayKey, "2026-06-10")
        let weekKey = TradingRuleScopeMath.easternWeekKey(dayKey: dayKey, from: wednesday)
        XCTAssertEqual(weekKey, "2026-06-08")
    }

    func testEasternWeekKeyAroundDSTStart() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        // US DST 2026 starts Sunday March 8 — use Monday March 9.
        let monday = calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 12))!
        let dayKey = TradingSessionLabel.easternTradeDateString(from: monday)
        let weekKey = TradingRuleScopeMath.easternWeekKey(dayKey: dayKey, from: monday)
        XCTAssertEqual(weekKey, "2026-03-09")
    }

    // MARK: - Scope / account filter

    func testPersistedYtdRestoresAsCalendarYearScope() {
        let profileID = ProfileID("scope-ytd-user")
        DashboardScopeFilterPersistence.save(
            profileID: profileID,
            stored: DashboardScopeFilterPersistence.Stored(
                dateRangeRaw: DashboardDateRange.ytd.rawValue,
                customStart: nil,
                customEnd: nil,
                accountModeRaw: nil,
                showPublicOnly: nil,
                hasUserSelectedDateRange: true,
                accountFilterKey: "all"
            )
        )
        defer {
            UserDefaults.standard.removeObject(
                forKey: "dashboard.scopeFilters.v1.\(profileID.rawValue)"
            )
        }

        let resolved = PsychologyAnalyticsScopeResolver.resolve(profileID: profileID, linkedAccountModes: [:])
        XCTAssertEqual(resolved.filter.dateRange, .ytd)
        XCTAssertEqual(DashboardTimePeriodPicker(dateRange: .ytd, usesCustomRange: false), .ytd)
    }

    func testPersistedAccountFilterRestoresIntoScopeResolver() {
        let profileID = ProfileID("scope-account-filter-user")
        DashboardScopeFilterPersistence.save(
            profileID: profileID,
            stored: DashboardScopeFilterPersistence.Stored(
                dateRangeRaw: DashboardDateRange.thirtyDays.rawValue,
                customStart: nil,
                customEnd: nil,
                accountModeRaw: nil,
                showPublicOnly: nil,
                hasUserSelectedDateRange: nil,
                accountFilterKey: accountID.rawValue
            )
        )
        defer {
            UserDefaults.standard.removeObject(
                forKey: "dashboard.scopeFilters.v1.\(profileID.rawValue)"
            )
        }

        let resolved = PsychologyAnalyticsScopeResolver.resolve(profileID: profileID, linkedAccountModes: [:])
        if case .account(let id) = resolved.filter.accountFilter {
            XCTAssertEqual(id, accountID)
        } else {
            XCTFail("Expected account filter")
        }

        let dashboardFingerprint = PsychologyAnalyticsScopeResolver.fingerprint(
            profileID: profileID,
            scope: resolved.filter
        )
        XCTAssertEqual(resolved.fingerprint, dashboardFingerprint)
    }

    // MARK: - Fixtures

    private func globalWithSessions(_ sessions: [String]) -> TradingPreferenceGlobal {
        var global = TradingPreferenceGlobal.empty(userID: profileID)
        global.preferredSessions = sessions
        return global
    }

    private func globalRevision(effectiveFrom: Date, sessions: [String]) -> TradingPreferenceRevision {
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

    private func preferenceContext(
        revisions: [TradingPreferenceRevision],
        global: TradingPreferenceGlobal,
        applyPast: Bool
    ) -> PreferenceRuleContext {
        var global = global
        global.applyRulesToPastTrades = applyPast
        return PreferenceRuleContext(revisions: revisions, global: global, overrides: [])
    }

    private func makeTrade(id: String, entryAt: Date, session: String) -> Trade {
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
            entryAt: entryAt,
            exitAt: entryAt.addingTimeInterval(300),
            realizedPnL: Money(amount: 50),
            sessionLabel: session,
            visibility: .private,
            createdAt: entryAt,
            updatedAt: entryAt
        )
    }
}
