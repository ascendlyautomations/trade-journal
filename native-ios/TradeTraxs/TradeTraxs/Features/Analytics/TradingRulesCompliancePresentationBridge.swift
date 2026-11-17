import Foundation

@MainActor
enum TradingRulesCompliancePresentationBridge {
    private(set) static weak var dashboardViewModel: DashboardViewModel?

    static func bind(_ viewModel: DashboardViewModel) {
        dashboardViewModel = viewModel
    }

    static func refresh(
        dependencies: TradingRulesComplianceLoadDependencies
    ) async -> TradingRulesComplianceLoadOutcome {
        await TradingRulesComplianceSessionLoader.refresh(
            dependencies: dependencies,
            dashboardViewModel: dashboardViewModel
        )
    }

    static func revealCachedSnapshotIfPossible(
        profileID: ProfileID,
        detailCache: DetailPresentationCache
    ) -> Bool {
        _ = SessionOwnerTradesStore.shared.hydrateFromDiskIfNeeded(
            for: profileID,
            detailCache: detailCache
        )
        return TradingRulesComplianceSessionLoader.revealCachedSnapshotIfPossible(
            profileID: profileID,
            dashboardViewModel: dashboardViewModel
        )
    }
}
