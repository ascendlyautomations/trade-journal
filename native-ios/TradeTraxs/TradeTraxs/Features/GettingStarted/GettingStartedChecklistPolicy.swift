import Foundation

/// Web-parity checklist rules — mirrors `lib/gettingStartedChecklist.ts`.
nonisolated enum GettingStartedChecklistPolicy {
    static func computeProgress(from signals: GettingStartedSignals) -> GettingStartedProgress {
        let tasks: [GettingStartedTask] = [
            GettingStartedTask(
                id: .profile,
                label: GettingStartedTaskID.profile.label,
                isComplete: signals.onboardingCompleted
            ),
            GettingStartedTask(
                id: .trade,
                label: GettingStartedTaskID.trade.label,
                isComplete: signals.tradeCount > 0
            ),
            GettingStartedTask(
                id: .dailyCheckIn,
                label: GettingStartedTaskID.dailyCheckIn.label,
                isComplete: signals.hasCompletedDailyCheckIn
            ),
            GettingStartedTask(
                id: .follow,
                label: GettingStartedTaskID.follow.label,
                isComplete: signals.followCount > 0
            ),
            GettingStartedTask(
                id: .room,
                label: GettingStartedTaskID.room.label,
                isComplete: signals.hasEverJoinedOtherRoom
            ),
            GettingStartedTask(
                id: .publicTrade,
                label: GettingStartedTaskID.publicTrade.label,
                isComplete: signals.hasPublicTrade
            ),
            GettingStartedTask(
                id: .post,
                label: GettingStartedTaskID.post.label,
                isComplete: signals.hasCreatedProfilePost
            ),
        ]

        let completedCount = tasks.filter(\.isComplete).count
        return GettingStartedProgress(
            tasks: tasks,
            completedCount: completedCount,
            totalCount: GettingStartedProgress.totalCount,
            allComplete: completedCount == GettingStartedProgress.totalCount
        )
    }

    /// Dashboard card visibility.
    ///
    /// Native has no navbar fallback, so the card stays until every required
    /// item is complete. `tradeCount` and `has_seen_onboarding_complete_popup`
    /// do not hide an incomplete list. Session dismiss is the permanent
    /// control and applies only after every item is done, which already hides
    /// the card.
    static func shouldShowDashboardCard(
        userID: String?,
        signals: GettingStartedSignals,
        progress: GettingStartedProgress,
        sessionDismissed: Bool
    ) -> Bool {
        guard let userID, !userID.isEmpty else { return false }
        guard signals.onboardingCompleted else { return false }
        return !progress.allComplete
    }

    /// True when checklist item data proves full completion but the profile flag is stale.
    static func needsServerCompletionReconciliation(
        signals: GettingStartedSignals,
        progress: GettingStartedProgress
    ) -> Bool {
        progress.allComplete && !signals.hasSeenOnboardingCompletePopup
    }

    /// Intro popup is disabled on web — keep native aligned.
    static func shouldShowIntroPopup(
        onboardingCompleted: Bool,
        hasSeenGettingStartedIntro: Bool
    ) -> Bool {
        false
    }
}
