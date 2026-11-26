import XCTest
@testable import TradeTraxs

@MainActor
final class PsychologyAnalyticsFreePreviewTests: XCTestCase {
    override func tearDown() {
        PsychologyAnalyticsPreviewSupport.endEphemeralHistoryPreview()
        CheckInHistorySessionStore.shared.invalidate()
        TraxsProPreviewSession.shared.endActivePreview(detailCache: DetailPresentationCache())
        super.tearDown()
    }

    func testSamplePresentationBuildsPsychologyHistoryRows() {
        let presentation = PsychologyAnalyticsPreviewSupport.buildSamplePresentation()
        XCTAssertGreaterThan(presentation.report.baseline.tradeCount, 0)
        XCTAssertGreaterThan(presentation.unlockProgress.tradingDayCheckInCount, 0)
        XCTAssertGreaterThanOrEqual(
            presentation.historySummaries.count,
            PsychologyAnalyticsPreviewSupport.inlineHistoryPreviewCount,
            "expected enough psychology days for the inline History preview"
        )
    }

    func testDashboardPreviewUsesIsolatedCheckInHistoryWithoutSessionStoreSeeding() {
        let profileID = ProfileID("free-preview-user")
        let cache = DetailPresentationCache()
        TraxsProPreviewSession.shared.beginDashboardPreview(detailCache: cache, viewer: profileID)
        defer { TraxsProPreviewSession.shared.endDashboardPreview(detailCache: cache) }

        let summaries = PsychologyAnalyticsPreviewSupport.sampleCheckInSummaries()
        XCTAssertGreaterThan(summaries.count, 0)
        XCTAssertTrue(CheckInHistorySessionStore.shared.summaries.isEmpty)
        XCTAssertTrue(PsychologyAnalyticsPreviewSupport.usesSampleCheckInHistory)
    }

    func testDashboardPreviewPsychologyDoesNotPublishIntoProductionSessionStore() async {
        PsychologyAnalyticsSessionStore.shared.clearSession()
        let profileID = ProfileID("psych-preview-isolation")
        let cache = DetailPresentationCache()

        TraxsProPreviewSession.shared.beginDashboardPreview(detailCache: cache, viewer: profileID)
        defer { TraxsProPreviewSession.shared.endDashboardPreview(detailCache: cache) }

        guard let previewData = TraxsProPreviewSession.shared.activePreviewEnvironment?.data else {
            XCTFail("missing preview environment")
            return
        }

        let viewModel = DashboardViewModel(
            home: TraxsProPreviewPsychIsolationStubHome(),
            trades: previewData.trades,
            achievements: TraxsProPreviewPsychIsolationEmptyAchievements(),
            dailyCheckIns: previewData.dailyCheckIns,
            session: TraxsProPreviewPsychIsolationStubSession(userID: profileID.rawValue),
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

        XCTAssertNotNil(viewModel.psychologyReport)
        XCTAssertNil(PsychologyAnalyticsSessionStore.shared.report)
        XCTAssertNil(PsychologyAnalyticsSessionStore.shared.profileID)
    }

    func testEphemeralLifecycleDoesNotPersistSampleHistoryInSessionStore() {
        PsychologyAnalyticsPreviewSupport.beginEphemeralHistoryPreview()
        XCTAssertTrue(PsychologyAnalyticsPreviewSupport.usesSampleCheckInHistory)
        XCTAssertFalse(PsychologyAnalyticsPreviewSupport.sampleCheckInSummaries().isEmpty)
        XCTAssertTrue(CheckInHistorySessionStore.shared.summaries.isEmpty)

        PsychologyAnalyticsPreviewSupport.endEphemeralHistoryPreview()
        XCTAssertFalse(PsychologyAnalyticsPreviewSupport.usesSampleCheckInHistory)
        XCTAssertTrue(CheckInHistorySessionStore.shared.summaries.isEmpty)
    }
}

private struct TraxsProPreviewPsychIsolationStubSession: SessionProviding {
    let userID: String
    var currentUserID: UserID? { get async { UserID(userID) } }
    var accessToken: String? { get async { nil } }
}

private struct TraxsProPreviewPsychIsolationStubHome: HomeRepository {
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

private struct TraxsProPreviewPsychIsolationEmptyAchievements: AchievementRepository {
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