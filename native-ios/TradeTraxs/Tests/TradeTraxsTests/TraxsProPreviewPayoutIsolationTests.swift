import XCTest
@testable import TradeTraxs

@MainActor
final class TraxsProPreviewPayoutIsolationTests: XCTestCase {
    private let viewer = ProfileID("payout-isolation-viewer")

    override func tearDown() {
        TraxsProPreviewSession.shared.endActivePreview(detailCache: DetailPresentationCache())
        WithdrawalsHistoryStore.shared.invalidate()
        SessionPayoutEntriesStore.shared.invalidate(profileID: viewer)
        SessionPayoutCyclesStore.shared.invalidate(profileID: viewer)
        super.tearDown()
    }

    func testDashboardPreviewDoesNotWriteWithdrawalsHistoryStore() async {
        let productionCache = DetailPresentationCache()
        let canonicalAccount = DemoCanonicalDataset.evaluationAccountID
        let beforeLedger = WithdrawalsHistoryStore.shared.ledgerByAccount

        TraxsProPreviewSession.shared.beginDashboardPreview(detailCache: productionCache, viewer: viewer)
        guard let previewData = TraxsProPreviewSession.shared.activePreviewEnvironment?.data else {
            XCTFail("missing preview environment")
            return
        }

        let viewModel = DashboardViewModel(
            home: TraxsProPreviewPayoutTestsStubHomeRepository(),
            trades: previewData.trades,
            achievements: TraxsProPreviewPayoutTestsEmptyAchievements(),
            dailyCheckIns: previewData.dailyCheckIns,
            session: TraxsProPreviewPayoutTestsStubSession(userID: viewer.rawValue),
            detailCache: previewData.detailCache,
            navigationCoordinator: NavigationCoordinator(store: NavigationStore()),
            tradingPreferences: previewData.tradingPreferences,
            loadsTraxsProPreviewSampleOnly: true
        )
        viewModel.loadIfNeeded()

        let deadline = Date().addingTimeInterval(6)
        while viewModel.phase != .loaded {
            if Date() > deadline {
                XCTFail("dashboard preview did not load")
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        guard let preview = TraxsProPreviewSession.shared.activePreviewEnvironment else {
            XCTFail("missing preview environment during load")
            return
        }
        XCTAssertFalse(preview.payoutEntriesByAccount.isEmpty, "preview env should carry sample payouts")
        XCTAssertEqual(beforeLedger, WithdrawalsHistoryStore.shared.ledgerByAccount)
        XCTAssertNil(WithdrawalsHistoryStore.shared.ledgerByAccount[canonicalAccount])

        TraxsProPreviewCoordinator.shared.dismissPreview(detailCache: productionCache)
        XCTAssertEqual(beforeLedger, WithdrawalsHistoryStore.shared.ledgerByAccount)
    }

    func testDashboardPreviewPayoutCardUsesSampleWithoutWithdrawalsStore() async {
        let productionCache = DetailPresentationCache()
        let beforeLedger = WithdrawalsHistoryStore.shared.ledgerByAccount

        TraxsProPreviewSession.shared.beginDashboardPreview(detailCache: productionCache, viewer: viewer)
        defer { TraxsProPreviewCoordinator.shared.dismissPreview(detailCache: productionCache) }

        guard let previewData = TraxsProPreviewSession.shared.activePreviewEnvironment?.data else {
            XCTFail("missing preview environment")
            return
        }

        let viewModel = DashboardViewModel(
            home: TraxsProPreviewPayoutTestsStubHomeRepository(),
            trades: previewData.trades,
            achievements: TraxsProPreviewPayoutTestsEmptyAchievements(),
            dailyCheckIns: previewData.dailyCheckIns,
            session: TraxsProPreviewPayoutTestsStubSession(userID: viewer.rawValue),
            detailCache: previewData.detailCache,
            navigationCoordinator: NavigationCoordinator(store: NavigationStore()),
            tradingPreferences: previewData.tradingPreferences,
            loadsTraxsProPreviewSampleOnly: true
        )
        viewModel.loadIfNeeded()

        let deadline = Date().addingTimeInterval(6)
        while viewModel.phase != .loaded {
            if Date() > deadline {
                XCTFail("dashboard preview did not load")
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        guard let preview = TraxsProPreviewSession.shared.activePreviewEnvironment else {
            XCTFail("missing preview environment after load")
            return
        }
        XCTAssertFalse(preview.payoutEntriesByAccount.isEmpty)
        XCTAssertNotNil(viewModel.summary, "preview dashboard should publish a summary including payouts math")
        XCTAssertEqual(beforeLedger, WithdrawalsHistoryStore.shared.ledgerByAccount)
        XCTAssertTrue(WithdrawalsHistoryStore.shared.ledgerByAccount.isEmpty)
    }

    func testExpenseTrackerPreviewDoesNotSeedSessionPayoutStores() async {
        let productionCache = DetailPresentationCache()
        let beforeLedger = WithdrawalsHistoryStore.shared.ledgerByAccount
        let beforeEntries = SessionPayoutEntriesStore.shared.all(for: viewer)

        TraxsProPreviewSession.shared.beginExpenseTrackerPreview(
            detailCache: productionCache,
            viewer: viewer
        )
        defer { TraxsProPreviewSession.shared.endExpenseTrackerPreview(detailCache: productionCache) }

        guard let previewData = TraxsProPreviewSession.shared.activePreviewEnvironment?.data else {
            XCTFail("missing preview environment")
            return
        }

        let viewModel = PropFirmExpensesViewModel(
            data: previewData,
            loadsTraxsProPreviewSampleOnly: true
        )
        await viewModel.load()

        XCTAssertFalse(viewModel.propPayoutItems.isEmpty)
        XCTAssertGreaterThan(viewModel.payouts, 0)
        XCTAssertEqual(beforeLedger, WithdrawalsHistoryStore.shared.ledgerByAccount)
        XCTAssertEqual(beforeEntries, SessionPayoutEntriesStore.shared.all(for: viewer))
        for accountID in DemoCanonicalDataset.accounts(owner: viewer).map(\.id) {
            XCTAssertNil(SessionPayoutCyclesStore.shared.cached(for: accountID, profileID: viewer))
        }
    }
}

private struct TraxsProPreviewPayoutTestsStubSession: SessionProviding {
    let userID: String
    var currentUserID: UserID? { get async { UserID(userID) } }
    var accessToken: String? { get async { nil } }
}

private struct TraxsProPreviewPayoutTestsStubHomeRepository: HomeRepository {
    func dashboard(for profileID: ProfileID) async throws -> HomeDashboard {
        HomeDashboard(
            summary: PerformanceSummary(
                interval: DateIntervalValue(start: Date(), end: Date()),
                statistics: TradeStatistics(
                    tradeCount: 0,
                    winCount: 0,
                    lossCount: 0,
                    totalPnL: Money(amount: 0),
                    averagePnL: Money(amount: 0),
                    averageRiskReward: nil,
                    winRate: 0
                ),
                bestTradeID: nil,
                worstTradeID: nil,
                currentStreakDays: 0
            ),
            widgets: [],
            insights: [],
            shortcutDestinations: [],
            refreshedAt: Date()
        )
    }

    func performance(for profileID: ProfileID, interval: DateIntervalValue) async throws -> PerformanceSummary {
        try await dashboard(for: profileID).summary
    }
}

private struct TraxsProPreviewPayoutTestsEmptyAchievements: AchievementRepository {
    func achievements(
        for profileID: ProfileID,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Achievement> {
        CursorPage(items: [], nextCursor: nil)
    }

    func achievement(id: AchievementID) async throws -> Achievement {
        throw AppError.unknown(message: "missing")
    }

    func save(_ achievement: Achievement, metadata: JSONValue?) async throws -> Achievement { achievement }
    func delete(id: AchievementID) async throws {}
    func withdrawalAchievementLinks(for profileID: ProfileID) async throws -> [WithdrawalAchievementLinkRow] { [] }
}