import XCTest
@testable import TradeTraxs

@MainActor
final class TradingRulesAnalyticsFreePreviewTests: XCTestCase {
    override func tearDown() {
        TradingRulesAnalyticsPreviewSupport.endEphemeralSampleIfNeeded(
            profileID: nil,
            detailCache: DetailPresentationCache()
        )
        TraxsProPreviewSession.shared.endActivePreview(detailCache: DetailPresentationCache())
        super.tearDown()
    }

    func testEphemeralSampleSeedsCanonicalPreferences() {
        let profileID = ProfileID("rules-free-preview")
        let cache = DetailPresentationCache()

        TradingRulesAnalyticsPreviewSupport.beginEphemeralSampleIfNeeded(
            profileID: profileID,
            detailCache: cache
        )
        defer {
            TradingRulesAnalyticsPreviewSupport.endEphemeralSampleIfNeeded(
                profileID: profileID,
                detailCache: cache
            )
        }

        XCTAssertTrue(TradingRulesAnalyticsPreviewSupport.showsSampleDataChrome)
        XCTAssertNotNil(TradingRulesCompliancePreferencesCache.cachedContext(for: profileID))
        XCTAssertGreaterThan(SessionOwnerTradesStore.shared.cached(for: profileID)?.count ?? 0, 0)
    }

    func testTradeNavigationGuardInSampleMode() {
        let sampleID = DemoCanonicalDataset.trades().first!.id
        let foreignID = TradeID("not-in-sample")

        TradingRulesAnalyticsPreviewSupport.beginEphemeralSampleIfNeeded(
            profileID: ProfileID("rules-guard"),
            detailCache: DetailPresentationCache()
        )
        defer {
            TradingRulesAnalyticsPreviewSupport.endEphemeralSampleIfNeeded(
                profileID: ProfileID("rules-guard"),
                detailCache: DetailPresentationCache()
            )
        }

        XCTAssertTrue(TradingRulesAnalyticsPreviewSupport.allowsTradeDetailNavigation(tradeID: sampleID))
        XCTAssertFalse(TradingRulesAnalyticsPreviewSupport.allowsTradeDetailNavigation(tradeID: foreignID))
    }
}