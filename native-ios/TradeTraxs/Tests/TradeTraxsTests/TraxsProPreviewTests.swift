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

    func testJournalPolicyUsesCanonicalDataOnlyForExploreDemoProfile() {
        let signedInViewer = ProfileID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        XCTAssertFalse(JournalSampleDataPolicy.usesCanonicalJournalData(for: signedInViewer))

        let cache = DetailPresentationCache()
        TraxsProPreviewSession.shared.beginReportsPreview(detailCache: cache, viewer: signedInViewer)
        XCTAssertFalse(JournalSampleDataPolicy.usesCanonicalJournalData(for: signedInViewer))
        TraxsProPreviewSession.shared.endReportsPreview(detailCache: cache)

        TraxsProPreviewSession.shared.beginDashboardPreview(detailCache: cache, viewer: signedInViewer)
        XCTAssertFalse(JournalSampleDataPolicy.usesCanonicalJournalData(for: signedInViewer))
        TraxsProPreviewSession.shared.endDashboardPreview(detailCache: cache)

        XCTAssertTrue(JournalSampleDataPolicy.usesCanonicalJournalData(for: DemoExperienceSupport.profileID))
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

    func testPreviewDoesNotSeedProductionDetailCache() {
        let cache = DetailPresentationCache()
        let owned = ProfileTradeFixtures.samples(owner: ProfileID("dev.preview.owner")).first
        if let owned {
            cache.seed(owned)
        }

        let viewer = ProfileID("dev.preview.owner")
        TraxsProPreviewSession.shared.beginReportsPreview(detailCache: cache, viewer: viewer)
        let demoID = DemoCanonicalDataset.trades().first?.id
        if let demoID {
            XCTAssertNil(cache.trade(id: demoID), "bundled trades belong in the preview cache only")
            XCTAssertNotNil(
                TraxsProPreviewSession.shared.activePreviewEnvironment?.data.detailCache.trade(id: demoID)
            )
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
        XCTAssertTrue(TraxsProPreviewCatalog.supportsInteractivePreview(for: .backtestLab))
        XCTAssertEqual(TraxsProPreviewCatalog.previewFeature(for: .backtestLab), .backtestLab)
        XCTAssertEqual(
            MonetizationPlanCopy.paywallPreviewFeatureTitle(for: .backtestLab),
            "Preview Backtest"
        )
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

        guard let previewData = TraxsProPreviewSession.shared.activePreviewEnvironment?.data else {
            XCTFail("expected isolated preview data environment")
            return
        }

        let viewModel = DashboardViewModel(
            home: TraxsProPreviewTestsStubHomeRepository(),
            trades: previewData.trades,
            achievements: TraxsProPreviewTestsEmptyAchievementRepository(),
            dailyCheckIns: previewData.dailyCheckIns,
            session: TraxsProPreviewTestsStubSession(userID: freeUserID),
            detailCache: previewData.detailCache,
            navigationCoordinator: NavigationCoordinator(store: NavigationStore()),
            tradingPreferences: previewData.tradingPreferences,
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
            "–",
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
        XCTAssertNotNil(summary.profitFactor)
        XCTAssertGreaterThan(summary.profitFactor ?? 0, 0)
        XCTAssertNotNil(summary.averageMaxRrReached, "avg max R:R should compute from sample maxRrReached values")
        let scopeMetrics = viewModel.traxsProPreviewScopeMetrics
        XCTAssertNotNil(scopeMetrics?.bestDayLabel)
        XCTAssertNotNil(scopeMetrics?.bestDayPnl)
        XCTAssertNotNil(scopeMetrics?.worstDayLabel)
        XCTAssertNotNil(scopeMetrics?.worstDayPnl)
        XCTAssertNotNil(scopeMetrics?.bestSessionLabel)
        XCTAssertNotNil(scopeMetrics?.worstSessionLabel)
        XCTAssertNotNil(scopeMetrics?.profitFactor)
    }

    func testExpenseTrackerPreviewSessionIsIsolatedFromJournal() {
        TraxsProPreviewSession.shared.beginExpenseTrackerPreview()
        XCTAssertTrue(TraxsProPreviewSession.shared.isExpenseTrackerPreviewActive)
        XCTAssertFalse(JournalSampleDataPolicy.usesCanonicalJournalData(for: ProfileID(freeUserID)))
        TraxsProPreviewSession.shared.endExpenseTrackerPreview()
        XCTAssertFalse(TraxsProPreviewSession.shared.isAnyPreviewActive)
    }

    func testBacktestLabPreviewUnlocksLabWithoutMixingCanonicalJournal() {
        let profileID = ProfileID(freeUserID)
        XCTAssertTrue(
            ProMonetizationPolicy.shouldRestrictBacktestLab(
                demoModeActive: false,
                profileID: profileID
            )
        )

        let cache = DetailPresentationCache()
        TraxsProPreviewSession.shared.beginBacktestLabPreview(detailCache: cache, viewer: profileID)
        XCTAssertTrue(TraxsProPreviewSession.shared.isBacktestLabPreviewActive)
        XCTAssertFalse(JournalSampleDataPolicy.usesCanonicalJournalData(for: profileID))
        XCTAssertFalse(
            ProMonetizationPolicy.shouldRestrictBacktestLab(
                demoModeActive: false,
                profileID: profileID
            )
        )

        let sampleID = BacktestLabPreviewSampleData.trades(owner: profileID).first?.id
        if let sampleID {
            XCTAssertTrue(TraxsProPreviewSupport.allowsJournalTradeNavigation(tradeID: sampleID))
            XCTAssertNil(cache.trade(id: sampleID))
            XCTAssertNotNil(
                TraxsProPreviewSession.shared.activePreviewEnvironment?.data.detailCache.trade(id: sampleID)
            )
        }

        TraxsProPreviewSession.shared.endBacktestLabPreview(detailCache: cache)
        if let sampleID {
            XCTAssertNil(cache.trade(id: sampleID))
        }
    }

    func testBacktestLabPreviewViewModelUsesSampleStrategiesAndMetrics() async {
        let viewModel = BacktestLabViewModel(
            trades: TraxsProPreviewTestsEmptyTradeRepository(),
            session: TraxsProPreviewTestsStubSession(userID: freeUserID),
            detailCache: DetailPresentationCache(),
            tradeDetailRepository: NullTradeDetailRepository(),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore()),
            loadsTraxsProPreviewSampleOnly: true
        )
        await viewModel.refresh()
        XCTAssertEqual(viewModel.phase, .loaded)
        XCTAssertFalse(viewModel.allTrades.isEmpty)
        XCTAssertGreaterThanOrEqual(viewModel.strategyBreakdown.count, 3)
        XCTAssertGreaterThan(viewModel.metrics.tradeCount, 0)
        XCTAssertTrue(viewModel.strategyOptions.contains("Fair Value Gap"))
        XCTAssertTrue(viewModel.strategyOptions.contains("Liquidity Sweep"))
        XCTAssertTrue(viewModel.strategyOptions.contains("Opening Range Breakout"))
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

    func testDashboardRestoreAfterPreviewExitSupportsRapidAccountSwitch() async {
        SessionViewerGate.shared.resetForTesting()
        SessionViewerGate.shared.bind(freeUserID)
        BackendV2FeatureFlags.setFlagForTests(.dashboardAnalyticsV3, enabled: true)
        defer {
            BackendV2FeatureFlags.resetFlagsForTests()
            SessionViewerGate.shared.resetForTesting()
            DashboardAnalyticsAccountChartsStore.shared.invalidate()
        }

        let profileID = ProfileID(freeUserID)
        let accountA = TradingAccountID("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
        let accountB = TradingAccountID("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
        let cache = DetailPresentationCache()
        let liveAccount = TradingAccount(
            id: accountA,
            ownerProfileID: profileID,
            name: "Live A",
            category: .personal,
            mode: .live,
            size: nil,
            isActive: true,
            canAddTrades: true,
            accountNumber: nil
        )
        let secondAccount = TradingAccount(
            id: accountB,
            ownerProfileID: profileID,
            name: "Live B",
            category: .personal,
            mode: .live,
            size: nil,
            isActive: true,
            canAddTrades: true,
            accountNumber: nil
        )
        SessionAccountsStore.shared.seed(
            [liveAccount, secondAccount],
            for: profileID,
            detailCache: cache,
            kind: .rest
        )

        let now = Date()
        let ownerTrade = Trade(
            id: TradeID("owner-trade-live"),
            ownerProfileID: profileID,
            accountID: accountA,
            symbol: Symbol(ticker: "ES"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryPrice: 1,
            exitPrice: 2,
            entryAt: now,
            exitAt: now.addingTimeInterval(60),
            realizedPnL: Money(amount: 50),
            visibility: .private,
            createdAt: now,
            updatedAt: now
        )
        let demoTrade = DemoCanonicalDataset.trades().first!

        let viewModel = DashboardViewModel(
            home: TraxsProPreviewTestsStubHomeRepository(),
            trades: TraxsProPreviewTestsEmptyTradeRepository(),
            achievements: TraxsProPreviewTestsEmptyAchievementRepository(),
            dailyCheckIns: EmptyTraderDailyCheckInRepository(),
            session: TraxsProPreviewTestsStubSession(userID: freeUserID),
            detailCache: cache,
            navigationCoordinator: NavigationCoordinator(store: NavigationStore())
        )
        viewModel.seedLocalDashboardForTradingRules(
            profileID: profileID,
            preferences: nil,
            trades: [ownerTrade, demoTrade],
            accounts: [liveAccount, secondAccount]
        )
        viewModel.setAccountFilter(.account(accountA))
        let tokenBeforePreview = DashboardAnalyticsAccountChartsCoordinator.currentSelectionToken()

        TraxsProPreviewSession.shared.beginDashboardPreview(detailCache: cache, viewer: profileID)
        XCTAssertFalse(JournalSampleDataPolicy.usesCanonicalJournalData(for: profileID))
        DashboardAnalyticsAccountChartsStore.shared.markFailed(
            accountID: DemoCanonicalDataset.evaluationAccountID,
            revision: 0,
            nonRetryable: true
        )

        TraxsProPreviewCoordinator.shared.dismissPreview(detailCache: cache)
        XCTAssertFalse(JournalSampleDataPolicy.usesCanonicalJournalData(for: profileID))

        await viewModel.refreshAfterTraxsProPreviewDismissed(profileID: profileID)
        viewModel.restoreAfterCanonicalJournalPreviewEnded()
        let ownerScoped = viewModel.complianceScopedTradesForRules()
        XCTAssertEqual(ownerScoped.count, 1)
        XCTAssertFalse(JournalSampleDataPolicy.isCanonicalTrade(id: ownerScoped[0].id))

        viewModel.setAccountFilter(.account(accountB))
        XCTAssertEqual(viewModel.accountFilter, .account(accountB))
        let tokenAfterSwitch = DashboardAnalyticsAccountChartsCoordinator.currentSelectionToken()
        XCTAssertGreaterThan(tokenAfterSwitch, tokenBeforePreview)
        XCTAssertEqual(
            DashboardAnalyticsAccountChartsStore.shared.availability(accountID: accountB, revision: 0),
            .notRequested
        )
    }
}

@MainActor
private func resetPreviewSessionForTesting() {
    TraxsProPreviewRuntimeFlag.isReportsPreviewActive = false
    TraxsProPreviewRuntimeFlag.isDashboardPreviewActive = false
    TraxsProPreviewRuntimeFlag.isExpenseTrackerPreviewActive = false
    TraxsProPreviewRuntimeFlag.isTradingRulesPreviewActive = false
    TraxsProPreviewRuntimeFlag.isBacktestLabPreviewActive = false
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