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

    func testEphemeralPreviewSeedsInMemoryHistoryWithoutPersistence() {
        let profileID = ProfileID("free-preview-user")
        let cache = DetailPresentationCache()
        TraxsProPreviewSession.shared.beginDashboardPreview(detailCache: cache, viewer: profileID)
        defer { TraxsProPreviewSession.shared.endDashboardPreview(detailCache: cache) }

        XCTAssertFalse(CheckInHistorySessionStore.shared.summaries.isEmpty)
        XCTAssertTrue(PsychologyAnalyticsPreviewSupport.usesSampleCheckInHistory)
    }

    func testEphemeralLifecycleClearsSeededHistoryOutsideDashboardPreview() {
        PsychologyAnalyticsPreviewSupport.beginEphemeralHistoryPreview()
        XCTAssertTrue(PsychologyAnalyticsPreviewSupport.usesSampleCheckInHistory)
        XCTAssertFalse(CheckInHistorySessionStore.shared.summaries.isEmpty)

        PsychologyAnalyticsPreviewSupport.endEphemeralHistoryPreview()
        XCTAssertFalse(PsychologyAnalyticsPreviewSupport.usesSampleCheckInHistory)
        XCTAssertTrue(CheckInHistorySessionStore.shared.summaries.isEmpty)
    }
}