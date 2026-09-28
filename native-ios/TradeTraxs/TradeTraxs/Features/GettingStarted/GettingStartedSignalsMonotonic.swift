import Foundation

/// Monotonic merge for Getting Started checklist signals — true never regresses to false.
nonisolated enum GettingStartedSignalsMonotonic {
    static func merge(prior: GettingStartedSignals, server: GettingStartedSignals) -> GettingStartedSignals {
        GettingStartedSignals(
            onboardingCompleted: prior.onboardingCompleted || server.onboardingCompleted,
            hasSeenGettingStartedIntro:
                prior.hasSeenGettingStartedIntro || server.hasSeenGettingStartedIntro,
            hasSeenOnboardingCompletePopup:
                prior.hasSeenOnboardingCompletePopup || server.hasSeenOnboardingCompletePopup,
            tradeCount: max(prior.tradeCount, server.tradeCount),
            hasCreatedProfilePost: prior.hasCreatedProfilePost || server.hasCreatedProfilePost,
            profilePostCount: max(prior.profilePostCount, server.profilePostCount),
            followCount: max(prior.followCount, server.followCount),
            hasEverJoinedOtherRoom: prior.hasEverJoinedOtherRoom || server.hasEverJoinedOtherRoom,
            hasPublicTrade: prior.hasPublicTrade || server.hasPublicTrade,
            hasCompletedDailyCheckIn:
                prior.hasCompletedDailyCheckIn || server.hasCompletedDailyCheckIn,
            firstPrivateTradeID: prior.firstPrivateTradeID ?? server.firstPrivateTradeID
        )
    }
}
