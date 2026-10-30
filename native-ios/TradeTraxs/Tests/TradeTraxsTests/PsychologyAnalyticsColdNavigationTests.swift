import XCTest
@testable import TradeTraxs

@MainActor
final class PsychologyAnalyticsColdNavigationTests: XCTestCase {
    override func tearDown() {
        PsychologyAnalyticsSessionStore.shared.clearSession()
        SessionDailyCheckInsStore.shared.invalidate()
        SessionOwnerTradesStore.shared.invalidate()
        super.tearDown()
    }

    func testDefaultScopeUsesThirtyDayWindow() {
        let resolved = PsychologyAnalyticsScopeResolver.defaultScope(linkedAccountModes: [:])
        XCTAssertEqual(resolved.filter.dateRange, .thirtyDays)
        XCTAssertEqual(resolved.filter.accountFilter, .all)
        XCTAssertFalse(resolved.label.isEmpty)
    }

    func testScopeResolverUsesPersistedDashboardFilters() {
        let profileID = ProfileID("psych-scope-user")
        DashboardScopeFilterPersistence.save(
            profileID: profileID,
            stored: DashboardScopeFilterPersistence.Stored(
                dateRangeRaw: DashboardDateRange.sevenDays.rawValue,
                customStart: nil,
                customEnd: nil,
                accountModeRaw: ProfileStatisticsMetrics.Mode.live.rawValue,
                showPublicOnly: true,
                hasUserSelectedDateRange: true
            )
        )
        defer {
            UserDefaults.standard.removeObject(
                forKey: "dashboard.scopeFilters.v1.\(profileID.rawValue)"
            )
        }

        let resolved = PsychologyAnalyticsScopeResolver.resolve(
            profileID: profileID,
            linkedAccountModes: [:]
        )
        XCTAssertEqual(resolved.filter.dateRange, .sevenDays)
        XCTAssertEqual(resolved.filter.accountMode, .live)
        XCTAssertTrue(resolved.filter.showPublicOnly)
    }

    func testSessionStoreClearsOnProfileMismatch() {
        let profileA = ProfileID("profile-a")
        let profileB = ProfileID("profile-b")
        let scope = PsychologyAnalyticsScopeResolver.defaultScope(linkedAccountModes: [:])

        PsychologyAnalyticsReportComposer.publish(
            scopedTrades: [],
            checkIns: [],
            profileID: profileA,
            scope: scope
        )
        XCTAssertEqual(PsychologyAnalyticsSessionStore.shared.profileID, profileA)

        PsychologyAnalyticsSessionStore.shared.clearIfProfileMismatch(profileB)
        XCTAssertNil(PsychologyAnalyticsSessionStore.shared.profileID)
        XCTAssertNil(PsychologyAnalyticsSessionStore.shared.report)
    }

    func testColdRevealBuildsReportFromDiskBackedCaches() {
        let profileID = ProfileID("psych-cold-user")
        DashboardScopeFilterPersistence.save(
            profileID: profileID,
            stored: DashboardScopeFilterPersistence.Stored(
                dateRangeRaw: DashboardDateRange.all.rawValue,
                customStart: nil,
                customEnd: nil,
                accountModeRaw: nil,
                showPublicOnly: nil,
                hasUserSelectedDateRange: nil
            )
        )
        defer {
            UserDefaults.standard.removeObject(
                forKey: "dashboard.scopeFilters.v1.\(profileID.rawValue)"
            )
        }
        let trade = makeRecentTrade(id: "t1")
        SessionOwnerTradesStore.shared.seed(
            [trade],
            for: profileID,
            detailCache: DetailPresentationCache(),
            historyComplete: true,
            totalTradeCount: 1
        )
        let dayKey = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: trade)
        SessionDailyCheckInsStore.shared.seed(
            [makeCheckIn(date: dayKey)],
            for: profileID,
            range: (dayKey, dayKey)
        )

        let revealed = PsychologyAnalyticsSessionLoader.revealCachedReportIfPossible(
            profileID: profileID
        )

        XCTAssertTrue(revealed)
        XCTAssertNotNil(PsychologyAnalyticsSessionStore.shared.report)
        XCTAssertEqual(PsychologyAnalyticsSessionStore.shared.profileID, profileID)
        XCTAssertEqual(PsychologyAnalyticsSessionStore.shared.report?.baseline.tradeCount, 1)
    }

    func testDashboardScopeFingerprintDiffersFromDefaultWhenFiltersPersisted() {
        let profileID = ProfileID("psych-fingerprint-user")
        DashboardScopeFilterPersistence.save(
            profileID: profileID,
            stored: DashboardScopeFilterPersistence.Stored(
                dateRangeRaw: DashboardDateRange.ninetyDays.rawValue,
                customStart: nil,
                customEnd: nil,
                accountModeRaw: nil,
                showPublicOnly: nil,
                hasUserSelectedDateRange: nil
            )
        )
        defer {
            UserDefaults.standard.removeObject(
                forKey: "dashboard.scopeFilters.v1.\(profileID.rawValue)"
            )
        }

        let persisted = PsychologyAnalyticsScopeResolver.resolve(
            profileID: profileID,
            linkedAccountModes: [:]
        )
        let defaultScope = PsychologyAnalyticsScopeResolver.defaultScope(linkedAccountModes: [:])
        XCTAssertNotEqual(persisted.fingerprint, defaultScope.fingerprint)
    }

    // MARK: - Fixtures

    private let baseDate = Calendar.current.date(
        from: DateComponents(year: 2026, month: 9, day: 10, hour: 14)
    )!

    private func makeRecentTrade(id: String) -> Trade {
        let entry = Date()
        return Trade(
            id: TradeID(id),
            ownerProfileID: ProfileID("psych-cold-user"),
            accountID: nil,
            symbol: Symbol(ticker: "ES"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryPrice: 100,
            exitPrice: 110,
            entryAt: entry,
            exitAt: entry.addingTimeInterval(3600),
            realizedPnL: Money(amount: 25),
            riskReward: nil,
            points: nil,
            sessionLabel: "NY",
            visibility: .private,
            publicCaption: nil,
            confidence: nil,
            createdAt: entry,
            updatedAt: entry
        )
    }

    private func makeTrade(id: String, dayOffset: Int) -> Trade {
        let entry = Calendar.current.date(
            byAdding: .day,
            value: dayOffset,
            to: baseDate
        ) ?? baseDate
        return Trade(
            id: TradeID(id),
            ownerProfileID: ProfileID("psych-cold-user"),
            accountID: nil,
            symbol: Symbol(ticker: "ES"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryPrice: 100,
            exitPrice: 110,
            entryAt: entry,
            exitAt: entry.addingTimeInterval(3600),
            realizedPnL: Money(amount: 25),
            riskReward: nil,
            points: nil,
            sessionLabel: "NY",
            visibility: .private,
            publicCaption: nil,
            confidence: nil,
            createdAt: entry,
            updatedAt: entry
        )
    }

    private func makeCheckIn(date: String) -> TraderDailyCheckIn {
        TraderDailyCheckIn(
            id: TraderDailyCheckInID("c-\(date)"),
            ownerProfileID: ProfileID("psych-cold-user"),
            checkInDate: date,
            sleepHours: 7,
            sleepQuality: 4,
            morningRating: 4,
            stressLevel: 2,
            energyLevel: 4,
            focusLevel: 4,
            notes: nil,
            createdAt: baseDate,
            updatedAt: baseDate
        )
    }
}
