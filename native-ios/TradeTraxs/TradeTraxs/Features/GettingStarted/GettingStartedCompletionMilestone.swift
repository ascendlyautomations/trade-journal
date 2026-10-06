import Foundation

/// One-time Getting Started completion celebration.
///
/// Fires only when checklist progress moves from incomplete to fully complete
/// after a baseline snapshot exists. Account onboarding alone does not qualify.
nonisolated enum GettingStartedCompletionMilestone {
    static func shouldCelebrate(
        hasEstablishedBaseline: Bool,
        previousAllComplete: Bool,
        nextAllComplete: Bool,
        hasSeenCompletionPopup: Bool
    ) -> Bool {
        guard hasEstablishedBaseline else { return false }
        guard !hasSeenCompletionPopup else { return false }
        return !previousAllComplete && nextAllComplete
    }
}
