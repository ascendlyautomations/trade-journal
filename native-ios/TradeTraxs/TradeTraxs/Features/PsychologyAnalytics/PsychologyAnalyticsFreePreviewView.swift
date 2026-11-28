import SwiftUI

/// Sample Psychology Analytics — same ``PsychologyAnalyticsDetailView`` as Pro with banner + upgrade footer only.
struct PsychologyAnalyticsFreePreviewView: View {
    let presentation: PsychologyAnalyticsPreviewSupport.SamplePresentation
    let navigationCoordinator: NavigationCoordinator
    let data: DataEnvironment

    private var activeProfileID: ProfileID? {
        SessionBootstrapStore.shared.last.map { ProfileID($0.data.viewer.id) }
    }

    var body: some View {
        PsychologyAnalyticsDetailView(
            report: presentation.report,
            insightCards: presentation.displayInsightCards,
            unlockProgress: presentation.unlockProgress,
            postUnlockGapMessages: presentation.postUnlockGapMessages,
            onOpenCheckInHistory: {
                navigationCoordinator.pushHome(.checkInHistory)
            },
            injectedCoachSummary: presentation.coachSummary,
            showsSamplePreviewBanner: true,
            showsPreviewUpgradeFooter: true,
            navigationCoordinator: navigationCoordinator,
            preferences: data.tradingPreferences,
            viewerID: activeProfileID,
            detailCache: data.detailCache
        )
        .accessibilityIdentifier("psychologyAnalytics.freePreview")
    }
}