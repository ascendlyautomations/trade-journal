import XCTest
@testable import TradeTraxs

@MainActor
final class TraxsProPreviewTests: XCTestCase {
    private let freeUserID = "traxspro-preview-free-user"

    override func setUp() {
        super.setUp()
        IosSubscriptionReleaseConfiguration.setTestOverrides(paywall: true, enforcement: true)
        PersistedEntitlementSnapshotStore.save(
            EntitlementSnapshotRecord(
                userID: freeUserID,
                traxProActive: false,
                source: "none",
                accessExpiresAt: nil,
                revokedAt: nil,
                fetchedAt: Date()
            )
        )
    }

    override func tearDown() {
        resetPreviewSessionForTesting()
        TraxsProPreviewCoordinator.shared.resetForTesting()
        ProUpgradeCoordinator.shared.dismiss()
        ProductAnalyticsCoordinator.shared.bind(repository: nil)
        DemoSnapshotStore.shared.clearMemory()
        PersistedEntitlementSnapshotStore.clear(userID: freeUserID)
        IosSubscriptionReleaseConfiguration.resetTestOverrides()
        super.tearDown()
    }

    func testPreviewSessionDoesNotEnableExploreDemoMode() {
        XCTAssertFalse(ExploreModeSupport.isActive)
        XCTAssertFalse(AppLaunchController.shared.isDemoExperienceActive)
        let cache = DetailPresentationCache()
        TraxsProPreviewSession.shared.beginReportsPreview(detailCache: cache)
        XCTAssertTrue(TraxsProPreviewSession.shared.isReportsPreviewActive)
        XCTAssertFalse(ExploreModeSupport.isActive)
        TraxsProPreviewSession.shared.endReportsPreview(detailCache: cache)
    }

    func testJournalPolicyUsesCanonicalDataDuringActivePreview() {
        let viewer = ProfileID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        XCTAssertFalse(JournalSampleDataPolicy.usesCanonicalJournalData(for: viewer))

        let cache = DetailPresentationCache()
        TraxsProPreviewSession.shared.beginReportsPreview(detailCache: cache)
        XCTAssertTrue(JournalSampleDataPolicy.usesCanonicalJournalData(for: viewer))

        TraxsProPreviewSession.shared.endReportsPreview(detailCache: cache)
        TraxsProPreviewSession.shared.beginDashboardPreview(detailCache: cache, viewer: viewer)
        XCTAssertTrue(JournalSampleDataPolicy.usesCanonicalJournalData(for: viewer))

        TraxsProPreviewSession.shared.endDashboardPreview(detailCache: cache)
        XCTAssertFalse(JournalSampleDataPolicy.usesCanonicalJournalData(for: viewer))
    }

    func testShouldRestrictTradingReportsCatalogBypassedOnlyInPreview() {
        let profileID = ProfileID(freeUserID)
        XCTAssertTrue(
            ProMonetizationPolicy.shouldRestrictTradingReportsCatalog(
                demoModeActive: false,
                profileID: profileID
            )
        )

        let cache = DetailPresentationCache()
        TraxsProPreviewSession.shared.beginReportsPreview(detailCache: cache)
        XCTAssertFalse(
            ProMonetizationPolicy.shouldRestrictTradingReportsCatalog(
                demoModeActive: false,
                profileID: profileID
            )
        )
        TraxsProPreviewSession.shared.endReportsPreview(detailCache: cache)
    }

    func testPremiumFeaturePresentationUnrestrictedDuringDashboardPreview() {
        let profileID = ProfileID(freeUserID)
        XCTAssertEqual(
            ProMonetizationPolicy.premiumFeaturePresentation(
                demoModeActive: false,
                profileID: profileID
            ),
            .lockedPreview
        )

        let cache = DetailPresentationCache()
        TraxsProPreviewSession.shared.beginDashboardPreview(detailCache: cache, viewer: profileID)
        XCTAssertEqual(
            ProMonetizationPolicy.premiumFeaturePresentation(
                demoModeActive: false,
                profileID: profileID
            ),
            .unrestricted
        )
        TraxsProPreviewSession.shared.endDashboardPreview(detailCache: cache)
    }

    func testExitPreviewRemovesSeededTradesButNotArbitraryCache() {
        let cache = DetailPresentationCache()
        let owned = ProfileTradeFixtures.samples(owner: ProfileID("dev.preview.owner")).first
        if let owned {
            cache.seed(owned)
        }

        TraxsProPreviewSession.shared.beginReportsPreview(detailCache: cache)
        let demoID = DemoCanonicalDataset.trades().first?.id
        if let demoID {
            XCTAssertNotNil(cache.trade(id: demoID))
        }
        TraxsProPreviewSession.shared.endReportsPreview(detailCache: cache)

        if let demoID {
            XCTAssertNil(cache.trade(id: demoID))
        }
        if let owned {
            XCTAssertNotNil(cache.trade(id: owned.id))
        }
    }

    func testCatalogAllowsInteractivePreviewForReportsAndPremiumDashboard() {
        XCTAssertTrue(TraxsProPreviewCatalog.supportsInteractivePreview(for: .tradingReports))
        XCTAssertTrue(TraxsProPreviewCatalog.supportsInteractivePreview(for: .premiumAnalytics))
        XCTAssertEqual(TraxsProPreviewCatalog.previewFeature(for: .tradingReports), .reports)
        XCTAssertEqual(TraxsProPreviewCatalog.previewFeature(for: .premiumAnalytics), .dashboard)
        XCTAssertTrue(TraxsProPreviewCatalog.supportsInteractivePreview(for: .propFirm))
        XCTAssertEqual(TraxsProPreviewCatalog.previewFeature(for: .propFirm), .expenseTracker)
        XCTAssertFalse(TraxsProPreviewCatalog.supportsInteractivePreview(for: .backtestLab))
    }

    func testCoordinatorPreventsDuplicatePresentation() async {
        let analytics = RecordingAnalyticsRepository()
        ProductAnalyticsCoordinator.shared.bind(repository: analytics)
        ProductAnalyticsCoordinator.shared.resetSession()

        TraxsProPreviewCoordinator.shared.presentDashboardPreview(entryPoint: .dashboardGate)
        XCTAssertTrue(TraxsProPreviewCoordinator.shared.isPresented)
        TraxsProPreviewCoordinator.shared.presentDashboardPreview(entryPoint: .proUpgradeSheet)
        XCTAssertTrue(TraxsProPreviewCoordinator.shared.isPresented)

        try? await Task.sleep(for: .milliseconds(100))
        let started = analytics.events(named: ProductAnalyticsEventName.traxsProPreviewStarted.rawValue)
        XCTAssertEqual(started.count, 1)
        XCTAssertEqual(started.first?["entry_point"], TraxsProPreviewEntryPoint.dashboardGate.rawValue)

        let cache = DetailPresentationCache()
        let viewer = ProfileID(freeUserID)
        TraxsProPreviewSession.shared.beginDashboardPreview(detailCache: cache, viewer: viewer)
        TraxsProPreviewCoordinator.shared.dismissPreview(detailCache: cache)
    }

    func testResolvedPreviewFeaturePrefersContextOverride() {
        XCTAssertEqual(
            TraxsProPreviewCatalog.resolvedPreviewFeature(
                reason: .feature(.premiumAnalytics),
                preferred: .tradingRules,
                suppressPreview: false
            ),
            .tradingRules
        )
        XCTAssertNil(
            TraxsProPreviewCatalog.resolvedPreviewFeature(
                reason: .feature(.premiumAnalytics),
                preferred: nil,
                suppressPreview: true
            )
        )
    }

    func testScheduledPresentationAfterPaywallDismiss() {
        ProductAnalyticsCoordinator.shared.bind(repository: RecordingAnalyticsRepository())
        ProductAnalyticsCoordinator.shared.resetSession()
        ProUpgradeCoordinator.shared.present(reason: .feature(.premiumAnalytics))

        TraxsProPreviewCoordinator.shared.scheduleDashboardPreviewAfterPaywallDismiss(entryPoint: .proUpgradeSheet)
        XCTAssertFalse(ProUpgradeCoordinator.shared.isPresented)

        TraxsProPreviewCoordinator.shared.paywallDidDismiss()
        XCTAssertTrue(TraxsProPreviewCoordinator.shared.isPresented)
        XCTAssertEqual(
            TraxsProPreviewCoordinator.shared.presentationEntryPoint,
            TraxsProPreviewEntryPoint.proUpgradeSheet
        )
        XCTAssertEqual(TraxsProPreviewCoordinator.shared.presentingFeature, .dashboard)

        TraxsProPreviewCoordinator.shared.dismissPreview(detailCache: DetailPresentationCache())
    }

    func testPreviewExitAndUpgradeAnalytics() async {
        let analytics = RecordingAnalyticsRepository()
        ProductAnalyticsCoordinator.shared.bind(repository: analytics)
        ProductAnalyticsCoordinator.shared.resetSession()

        TraxsProPreviewCoordinator.shared.presentDashboardPreview(entryPoint: .featurePreviewCard)
        let viewer = ProfileID(freeUserID)
        TraxsProPreviewSession.shared.beginDashboardPreview(
            detailCache: DetailPresentationCache(),
            viewer: viewer
        )

        TraxsProPreviewCoordinator.shared.noteUpgradeTappedFromPreviewBanner()
        TraxsProPreviewCoordinator.shared.dismissPreview(detailCache: DetailPresentationCache())

        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(
            analytics.events(named: ProductAnalyticsEventName.traxsProPreviewUpgradeTapped.rawValue).count,
            1
        )
        XCTAssertEqual(
            analytics.events(named: ProductAnalyticsEventName.traxsProPreviewExited.rawValue).count,
            1
        )
    }

    @MainActor
    func testDashboardPreviewViewModelPopulatesPremiumChartMetrics() async {
        SessionViewerGate.shared.resetForTesting()
        SessionViewerGate.shared.bind(freeUserID)
        defer { SessionViewerGate.shared.resetForTesting() }

        BackendV2FeatureFlags.setFlagForTests(.dashboardAnalyticsV3, enabled: true)
        BackendV2FeatureFlags.setFlagForTests(.dashboard, enabled: true)
        defer { BackendV2FeatureFlags.resetFlagsForTests() }

        let profileID = ProfileID(freeUserID)
        let cache = DetailPresentationCache()
        TraxsProPreviewSession.shared.beginDashboardPreview(detailCache: cache, viewer: profileID)
        defer { TraxsProPreviewSession.shared.endDashboardPreview(detailCache: cache) }

        let viewModel = DashboardViewModel(
            home: TraxsProPreviewTestsStubHomeRepository(),
            trades: TraxsProPreviewTestsEmptyTradeRepository(),
            achievements: TraxsProPreviewTestsEmptyAchievementRepository(),
            dailyCheckIns: EmptyTraderDailyCheckInRepository(),
            session: TraxsProPreviewTestsStubSession(userID: freeUserID),
            detailCache: cache,
            navigationCoordinator: NavigationCoordinator(store: NavigationStore()),
            loadsTraxsProPreviewSampleOnly: true
        )
        viewModel.loadIfNeeded()

        let deadline = Date().addingTimeInterval(8)
        while viewModel.phase != .loaded || viewModel.summary == nil {
            if Date() > deadline {
                XCTFail("TraxsPro dashboard preview did not produce a summary")
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        guard let summary = viewModel.summary else {
            XCTFail("missing dashboard summary")
            return
        }
        XCTAssertGreaterThan(summary.tradeCount, 0, "expected scoped trades in preview")
        XCTAssertFalse(summary.holdTimeHistogram.isEmpty, "hold time chart should render")
        XCTAssertTrue(
            summary.hourHeatmap.contains(where: { abs($0.value) > 0.01 }),
            "trading hours chart should have sample data"
        )
        XCTAssertGreaterThanOrEqual(summary.rrTargetAnalysis.pairedCount, 5, "R:R targeting needs paired sample trades")
        XCTAssertNotNil(
            summary.rrTargetAnalysis.avgTargetAttainmentRatio,
            "R:R attainment should compute in preview"
        )
        XCTAssertNotNil(summary.hourHighlights, "trading hours should surface best/worst hours")
        XCTAssertNotEqual(
            summary.holdTime.first(where: { $0.label == "Avg Winner" })?.value,
            "—",
            "hold time should separate winners"
        )
        XCTAssertGreaterThanOrEqual(summary.holdExtremes.count, 2, "hold extremes need wins and losses")
        XCTAssertFalse(summary.drawdownSeries.isEmpty, "drawdown chart should render")
        let strategies = summary.strategyHighlights
        XCTAssertTrue(
            strategies?.best != nil || strategies?.worst != nil,
            "setup performance should include qualifying setups"
        )
        XCTAssertFalse(
            viewModel.dashboardPsychologyInsightCards.isEmpty,
            "psychology insights should populate from seeded check-ins"
        )
    }

    func testExpenseTrackerPreviewSessionIsIsolatedFromJournal() {
        TraxsProPreviewSession.shared.beginExpenseTrackerPreview()
        XCTAssertTrue(TraxsProPreviewSession.shared.isExpenseTrackerPreviewActive)
        XCTAssertFalse(JournalSampleDataPolicy.usesCanonicalJournalData(for: ProfileID(freeUserID)))
        TraxsProPreviewSession.shared.endExpenseTrackerPreview()
        XCTAssertFalse(TraxsProPreviewSession.shared.isAnyPreviewActive)
    }

    func testPreviewNavigationDoesNotGateOtherProFeatures() {
        let profileID = ProfileID(freeUserID)
        XCTAssertTrue(
            ProMonetizationPolicy.shouldRestrictBacktestLab(
                demoModeActive: false,
                profileID: profileID
            )
        )
        let cache = DetailPresentationCache()
        TraxsProPreviewSession.shared.beginDashboardPreview(detailCache: cache, viewer: profileID)
        XCTAssertTrue(
            ProMonetizationPolicy.shouldRestrictBacktestLab(
                demoModeActive: false,
                profileID: profileID
            )
        )
        TraxsProPreviewSession.shared.endDashboardPreview(detailCache: cache)
    }
}

@MainActor
private func resetPreviewSessionForTesting() {
    TraxsProPreviewRuntimeFlag.isReportsPreviewActive = false
    TraxsProPreviewRuntimeFlag.isDashboardPreviewActive = false
    TraxsProPreviewRuntimeFlag.isExpenseTrackerPreviewActive = false
    if TraxsProPreviewSession.shared.isAnyPreviewActive {
        TraxsProPreviewSession.shared.endActivePreview(detailCache: DetailPresentationCache())
    }
}

private struct TraxsProPreviewTestsStubSession: SessionProviding {
    let userID: String?
    var currentUserID: UserID? {
        get async {
            guard let userID else { return nil }
            return UserID(userID)
        }
    }
    var accessToken: String? { get async { nil } }
}

private struct TraxsProPreviewTestsStubHomeRepository: HomeRepository {
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

    func performance(
        for profileID: ProfileID,
        interval: DateIntervalValue
    ) async throws -> PerformanceSummary {
        try await dashboard(for: profileID).summary
    }
}

private struct TraxsProPreviewTestsEmptyTradeRepository: TradeRepository {
    func trade(id: TradeID) async throws -> Trade {
        throw AppError.unknown(message: "not found")
    }

    func trades(
        ownedBy profileID: ProfileID,
        accountID: TradingAccountID?,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Trade> {
        CursorPage(items: [], nextCursor: nil)
    }

    func save(_ draft: TradeDraft) async throws -> Trade {
        throw AppError.unknown(message: "stub")
    }

    func update(_ trade: Trade) async throws -> Trade { trade }
    func delete(id: TradeID) async throws {}
    func images(for tradeID: TradeID) async throws -> [TradeImage] { [] }
    func notes(for tradeID: TradeID) async throws -> [TradeNote] { [] }

    func statistics(
        for profileID: ProfileID,
        interval: DateIntervalValue
    ) async throws -> TradeStatistics {
        TradeStatistics(
            tradeCount: 0,
            winCount: 0,
            lossCount: 0,
            totalPnL: Money(amount: 0),
            averagePnL: Money(amount: 0),
            averageRiskReward: nil,
            winRate: 0
        )
    }

    func accounts(for profileID: ProfileID) async throws -> [TradingAccount] { [] }
}

private struct TraxsProPreviewTestsEmptyAchievementRepository: AchievementRepository {
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

    func save(_ achievement: Achievement, metadata: JSONValue?) async throws -> Achievement {
        achievement
    }

    func delete(id: AchievementID) async throws {}

    func withdrawalAchievementLinks(for profileID: ProfileID) async throws -> [WithdrawalAchievementLinkRow] {
        []
    }
}

private final class RecordingAnalyticsRepository: AnalyticsRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [[String: String]] = []

    func track(event: String, properties: [String: String]) async {
        lock.lock()
        var row = properties
        row["event_name"] = event
        rows.append(row)
        lock.unlock()
    }

    func events(named event: String) -> [[String: String]] {
        lock.lock()
        defer { lock.unlock() }
        return rows.filter { $0["event_name"] == event }
    }
}