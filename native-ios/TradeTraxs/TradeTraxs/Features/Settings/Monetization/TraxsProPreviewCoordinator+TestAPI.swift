#if DEBUG
import Foundation

extension TraxsProPreviewCoordinator {
    func dismissPreview(detailCache: DetailPresentationCache) {
        let production = DataEnvironment.traxsProPreviewTestHarness(
            detailCache: detailCache,
            session: TraxsProPreviewCoordinatorTestSession()
        )
        dismissPreview(productionData: production)
    }
}

private struct TraxsProPreviewCoordinatorTestSession: SessionProviding {
    var currentUserID: UserID? { get async { nil } }
    var accessToken: String? { get async { nil } }
}
#endif