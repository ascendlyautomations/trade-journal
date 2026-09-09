import SwiftUI

/// Scroll viewport frame for inline Feed clip visibility (global coordinates).
private struct FeedScrollViewportFrameKey: EnvironmentKey {
    static let defaultValue: CGRect = .zero
}

extension EnvironmentValues {
    var feedScrollViewportFrame: CGRect {
        get { self[FeedScrollViewportFrameKey.self] }
        set { self[FeedScrollViewportFrameKey.self] = newValue }
    }
}

enum FeedInlineClipVisibility {
    /// Visible height fraction of the clip card within the scroll viewport (0…1).
    static func fraction(viewFrame: CGRect, viewportFrame: CGRect) -> CGFloat {
        guard viewFrame.height > 1,
              viewportFrame.height > 1,
              viewFrame.width > 1,
              viewportFrame.width > 1
        else { return 0 }

        let intersection = viewFrame.intersection(viewportFrame)
        guard intersection.height > 0, intersection.width > 0 else { return 0 }
        return min(1, max(0, intersection.height / viewFrame.height))
    }
}

/// Reports measured viewport visibility for inline Feed clips (not onAppear/onDisappear).
struct FeedInlineClipVisibilityReporter: ViewModifier {
    let reel: Reel
    let playbackCoordinator: FeedVideoPlaybackCoordinator

    @Environment(\.feedScrollViewportFrame) private var viewportFrame

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self, of: { proxy in
                FeedInlineClipVisibility.fraction(
                    viewFrame: proxy.frame(in: .global),
                    viewportFrame: viewportFrame
                )
            }) { fraction in
                playbackCoordinator.updateInlineClipVisibility(reel: reel, fraction: fraction)
            }
    }
}

extension View {
    func feedInlineClipVisibilityReporting(
        reel: Reel,
        playbackCoordinator: FeedVideoPlaybackCoordinator
    ) -> some View {
        modifier(
            FeedInlineClipVisibilityReporter(
                reel: reel,
                playbackCoordinator: playbackCoordinator
            )
        )
    }
}
