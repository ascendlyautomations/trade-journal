#if DEBUG
import Foundation

extension TraxsProPreviewSession {
    func beginExpenseTrackerPreview(detailCache: DetailPresentationCache, viewer: ProfileID? = nil) {
        let viewerID = viewer ?? ProfileID("preview-test-viewer")
        let production = DataEnvironment.traxsProPreviewTestHarness(
            detailCache: detailCache,
            session: TraxsProPreviewTestSession(userID: viewerID.rawValue)
        )
        beginExpenseTrackerPreview(production: production, viewer: viewerID)
    }

    func beginExpenseTrackerPreview() {
        beginExpenseTrackerPreview(detailCache: DetailPresentationCache())
    }

    func endExpenseTrackerPreview(detailCache: DetailPresentationCache? = nil) {
        _ = detailCache
        endExpenseTrackerPreview()
    }

    func beginReportsPreview(detailCache: DetailPresentationCache, viewer: ProfileID? = nil) {
        let viewerID = viewer ?? ProfileID("preview-test-viewer")
        let production = DataEnvironment.traxsProPreviewTestHarness(
            detailCache: detailCache,
            session: TraxsProPreviewTestSession()
        )
        beginReportsPreview(production: production, viewer: viewerID)
    }

    func beginDashboardPreview(detailCache: DetailPresentationCache, viewer: ProfileID) {
        let production = DataEnvironment.traxsProPreviewTestHarness(
            detailCache: detailCache,
            session: TraxsProPreviewTestSession(userID: viewer.rawValue)
        )
        beginDashboardPreview(production: production, viewer: viewer)
    }

    func beginTradingRulesPreview(detailCache: DetailPresentationCache, viewer: ProfileID) {
        let production = DataEnvironment.traxsProPreviewTestHarness(
            detailCache: detailCache,
            session: TraxsProPreviewTestSession(userID: viewer.rawValue)
        )
        beginTradingRulesPreview(production: production, viewer: viewer)
    }

    func beginBacktestLabPreview(detailCache: DetailPresentationCache, viewer: ProfileID) {
        let production = DataEnvironment.traxsProPreviewTestHarness(
            detailCache: detailCache,
            session: TraxsProPreviewTestSession(userID: viewer.rawValue)
        )
        beginBacktestLabPreview(production: production, viewer: viewer)
    }

    func endReportsPreview(detailCache: DetailPresentationCache) {
        _ = detailCache
        endReportsPreview()
    }

    func endDashboardPreview(detailCache: DetailPresentationCache) {
        _ = detailCache
        endDashboardPreview()
    }

    func endTradingRulesPreview(detailCache: DetailPresentationCache) {
        _ = detailCache
        endTradingRulesPreview()
    }

    func endBacktestLabPreview(detailCache: DetailPresentationCache) {
        _ = detailCache
        endBacktestLabPreview()
    }

    func endActivePreview(detailCache: DetailPresentationCache) {
        _ = detailCache
        endActivePreview()
    }
}

private struct TraxsProPreviewTestSession: SessionProviding {
    let userID: String?
    init(userID: String? = nil) { self.userID = userID }
    var currentUserID: UserID? {
        get async {
            guard let userID else { return nil }
            return UserID(userID)
        }
    }
    var accessToken: String? { get async { nil } }
}
#endif