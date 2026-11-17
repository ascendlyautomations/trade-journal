import Foundation

/// Retains the Feed tab root presentation across `TabView` teardown and shallow rebuilds.
///
/// Matches ``DashboardTabModelStore`` — keeps timeline pagination and scroll anchors on the
/// same ``FeedScreenViewModel`` instance instead of cold-booting when the shell re-mounts.
@MainActor
enum FeedTabModelStore {
    private static var retainedViewModel: FeedScreenViewModel?
    private static var retainedPlayback: FeedVideoPlaybackCoordinator?
    private static var retainedListScrollAnchor: FeedListScrollAnchor?

    static func listScrollAnchor(restoredOffset: CGFloat?) -> FeedListScrollAnchor {
        if let retainedListScrollAnchor { return retainedListScrollAnchor }
        let created = FeedListScrollAnchor(restoredOffset: restoredOffset)
        retainedListScrollAnchor = created
        return created
    }

    static func presentation(
        retainsTabPresentation: Bool,
        makeViewModel: () -> FeedScreenViewModel,
        makePlayback: () -> FeedVideoPlaybackCoordinator
    ) -> (FeedScreenViewModel, FeedVideoPlaybackCoordinator) {
        guard retainsTabPresentation else {
            return (makeViewModel(), makePlayback())
        }
        if let retainedViewModel, let retainedPlayback {
            return (retainedViewModel, retainedPlayback)
        }
        let viewModel = makeViewModel()
        let playback = makePlayback()
        retainedViewModel = viewModel
        retainedPlayback = playback
        return (viewModel, playback)
    }

    static func scrollToTopWhenTabReselectedAtRoot() {
        retainedViewModel?.scrollToTopForTabReselect()
        retainedListScrollAnchor?.resetToTop()
    }

    static func resetForSessionBoundary() {
        retainedViewModel = nil
        retainedPlayback = nil
        retainedListScrollAnchor = nil
    }

    #if DEBUG
    static func clearForTesting() {
        retainedViewModel = nil
        retainedPlayback = nil
        retainedListScrollAnchor = nil
    }
    #endif
}