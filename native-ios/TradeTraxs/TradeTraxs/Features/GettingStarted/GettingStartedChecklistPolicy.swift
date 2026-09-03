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
                isComplete: signals.profilePostCount > 0
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

    /// Dashboard card visibility — mirrors `shouldAutoShowGettingStartedChecklist`.
    static func shouldShowDashboardCard(
        userID: String?,
        signals: GettingStartedSignals,
        progress: GettingStartedProgress,
        sessionDismissed: Bool
    ) -> Bool {
        guard let userID, !userID.isEmpty else { return false }
        guard signals.onboardingCompleted else { return false }
        guard !progress.allComplete else { return false }
        guard signals.tradeCount <= 0 else { return false }
        guard !sessionDismissed else { return false }
        return true
    }

    /// Intro popup is disabled on web — keep native aligned.
    static func shouldShowIntroPopup(
        onboardingCompleted: Bool,
        hasSeenGettingStartedIntro: Bool
    ) -> Bool {
        false
    }
}
