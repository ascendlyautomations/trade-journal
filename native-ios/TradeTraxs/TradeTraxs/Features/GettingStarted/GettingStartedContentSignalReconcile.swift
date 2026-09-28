import Foundation

/// Keeps profile-post vs public-trade Getting Started signals independent and server-aligned.
nonisolated enum GettingStartedContentSignalReconcile {
    /// When RPC confirms no `profile_posts`, drop false post completion (unless a local post hint is in flight).
    static func reconcilePostAgainstServer(
        effective: GettingStartedSignals,
        server: GettingStartedSignals,
        trustLocalProfilePostHint: Bool
    ) -> GettingStartedSignals {
        let serverHasPost = server.hasCreatedProfilePost
        guard !serverHasPost, !trustLocalProfilePostHint else { return effective }

        var repaired = effective
        if repaired.hasCreatedProfilePost || repaired.profilePostCount > 0 {
            repaired.hasCreatedProfilePost = false
            repaired.profilePostCount = 0
        }
        return repaired
    }

    static func normalizedPostFlags(_ signals: GettingStartedSignals) -> GettingStartedSignals {
        var copy = signals
        if copy.hasCreatedProfilePost {
            copy.profilePostCount = max(copy.profilePostCount, 1)
        } else if copy.profilePostCount <= 0 {
            copy.profilePostCount = 0
        }
        return copy
    }
}
