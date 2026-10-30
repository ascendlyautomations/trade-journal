import Foundation

@MainActor
enum PsychologyAnalyticsPresentationBridge {
    private static weak var dashboardViewModel: DashboardViewModel?

    static func bind(_ viewModel: DashboardViewModel) {
        dashboardViewModel = viewModel
    }

    static func refresh(
        dependencies: PsychologyAnalyticsLoadDependencies
    ) async -> PsychologyAnalyticsLoadOutcome {
        await PsychologyAnalyticsSessionLoader.refresh(
            dependencies: dependencies,
            dashboardViewModel: dashboardViewModel
        )
    }

    static func revealCachedReportIfPossible(
        profileID: ProfileID,
        detailCache: DetailPresentationCache
    ) -> Bool {
        _ = SessionOwnerTradesStore.shared.hydrateFromDiskIfNeeded(
            for: profileID,
            detailCache: detailCache
        )
        return PsychologyAnalyticsSessionLoader.revealCachedReportIfPossible(profileID: profileID)
    }
}
