import XCTest
@testable import TradeTraxs

/// Regression matrix for TraxsPro preview ↔ production data isolation.
@MainActor
final class TraxsProPreviewIsolationTests: XCTestCase {
    private let viewer = ProfileID("isolation-viewer")

    override func tearDown() {
        TraxsProPreviewSession.shared.endActivePreview(detailCache: DetailPresentationCache())
        TradingRulesComplianceSessionStore.shared.reset()
        TradingRulesCompliancePreferencesCache.resetAll()
        SessionOwnerTradesStore.shared.invalidate(profileID: viewer)
        super.tearDown()
    }

    func testRepeatedDashboardPreviewCyclesKeepProductionCacheClean() {
        let productionCache = DetailPresentationCache()
        let owned = ProfileTradeFixtures.samples(owner: viewer).first
        owned.map { productionCache.seed($0) }

        for cycle in 0..<3 {
            TraxsProPreviewSession.shared.beginDashboardPreview(
                detailCache: productionCache,
                viewer: viewer
            )
            let demoID = DemoCanonicalDataset.trades().first!.id
            XCTAssertNil(
                productionCache.trade(id: demoID),
                "cycle \(cycle): demo trade must not appear in production cache"
            )
            XCTAssertNotNil(
                TraxsProPreviewSession.shared.activePreviewEnvironment?.data.detailCache.trade(id: demoID)
            )
            TraxsProPreviewCoordinator.shared.dismissPreview(detailCache: productionCache)
            XCTAssertNil(productionCache.trade(id: demoID))
        }
        if let owned {
            XCTAssertNotNil(productionCache.trade(id: owned.id))
        }
    }

    func testPreviewEnvironmentIsDistinctFromProductionFork() {
        let productionCache = DetailPresentationCache()
        TraxsProPreviewSession.shared.beginReportsPreview(
            detailCache: productionCache,
            viewer: viewer
        )
        defer { TraxsProPreviewSession.shared.endReportsPreview(detailCache: productionCache) }

        guard let preview = TraxsProPreviewSession.shared.activePreviewEnvironment else {
            XCTFail("missing preview environment")
            return
        }
        XCTAssertFalse(preview.data.detailCache === productionCache)
    }

    func testRulesPresentationStoresStayIsolatedFromProduction() async {
        let productionCache = DetailPresentationCache()
        TradingRulesComplianceSessionStore.shared.reset()

        TraxsProPreviewSession.shared.beginTradingRulesPreview(
            detailCache: productionCache,
            viewer: viewer
        )
        guard let preview = TraxsProPreviewSession.shared.activePreviewEnvironment else {
            XCTFail("missing preview")
            return
        }

        let dependencies = TradingRulesComplianceLoadDependencies(
            detailCache: preview.data.detailCache,
            tradesRepository: preview.data.trades,
            tradingPreferences: preview.data.tradingPreferences
        )
        _ = await TradingRulesAnalyticsPreviewSupport.publishBundledSampleSnapshot(
            profileID: viewer,
            dependencies: dependencies,
            preferenceContext: preview.preferenceContext
        )

        XCTAssertTrue(preview.rulesPresentationStore.ready)
        XCTAssertFalse(TradingRulesComplianceSessionStore.shared.ready)
        XCTAssertNil(TradingRulesComplianceSessionStore.shared.result)

        TraxsProPreviewSession.shared.endTradingRulesPreview(detailCache: productionCache)
        XCTAssertFalse(preview.rulesPresentationStore.ready)
        XCTAssertNil(TradingRulesComplianceSessionStore.shared.result)
    }

    func testStalePreviewGenerationRejectsBundledSnapshotPublish() async {
        let productionCache = DetailPresentationCache()
        TraxsProPreviewSession.shared.beginTradingRulesPreview(
            detailCache: productionCache,
            viewer: viewer
        )
        guard let preview = TraxsProPreviewSession.shared.activePreviewEnvironment else {
            XCTFail("missing preview")
            return
        }
        preview.invalidateGeneration()

        let dependencies = TradingRulesComplianceLoadDependencies(
            detailCache: preview.data.detailCache,
            tradesRepository: preview.data.trades,
            tradingPreferences: preview.data.tradingPreferences
        )

        let published = await TradingRulesAnalyticsPreviewSupport.publishBundledSampleSnapshot(
            profileID: viewer,
            dependencies: dependencies,
            preferenceContext: preview.preferenceContext
        )
        XCTAssertFalse(published)
        TraxsProPreviewSession.shared.endTradingRulesPreview(detailCache: productionCache)
    }

    func testProductionOwnerTradesRemainAfterPreviewWithPopulatedJournal() async {
        let productionCache = DetailPresentationCache()
        guard let ownerTrade = ProfileTradeFixtures.samples(owner: viewer).first else {
            XCTFail("missing fixture trade")
            return
        }

        SessionOwnerTradesStore.shared.seed(
            [ownerTrade],
            for: viewer,
            detailCache: productionCache,
            historyComplete: true,
            totalTradeCount: 1
        )
        let beforeCount = SessionOwnerTradesStore.shared.cached(for: viewer)?.count ?? 0
        XCTAssertEqual(beforeCount, 1)

        TraxsProPreviewSession.shared.beginDashboardPreview(
            detailCache: productionCache,
            viewer: viewer
        )
        TraxsProPreviewCoordinator.shared.dismissPreview(detailCache: productionCache)

        let after = SessionOwnerTradesStore.shared.cached(for: viewer) ?? []
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after.first?.id, ownerTrade.id)
        XCTAssertFalse(JournalSampleDataPolicy.isCanonicalTrade(id: after.first!.id))
    }
}

private struct TraxsProPreviewIsolationStubSession: SessionProviding {
    var currentUserID: UserID? { get async { UserID("isolation-viewer") } }
    var accessToken: String? { get async { nil } }
}