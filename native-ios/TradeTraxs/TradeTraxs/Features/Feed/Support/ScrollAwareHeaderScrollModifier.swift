import SwiftUI

/// Shared scroll-geometry → header chrome hide/show (Feed timeline, Dashboard, …).
struct ScrollAwareHeaderScrollModifier: ViewModifier {
    let isActive: Bool
    let reduceMotion: Bool
    let debugSurface: String
    var trackingMode: FeedScrollAwareHeaderTrackingMode = .navigationBarInsetStable
    @Binding var tracker: FeedScrollAwareHeaderTracker
    @Binding var chromeHidden: Bool

    func body(content: Content) -> some View {
        if isActive {
            content
                .onScrollGeometryChange(for: FeedScrollChromeGeometrySample.self) { geometry in
                    FeedScrollChromeGeometrySample(
                        normalizedOffsetY: geometry.contentOffset.y + geometry.contentInsets.top,
                        rawOffsetY: geometry.contentOffset.y,
                        contentInsetTop: geometry.contentInsets.top
                    )
                } action: { _, sample in
                    let result = applyScrollSample(sample: sample)
                    #if DEBUG
                    FeedScrollAwareHeaderDiagnostics.logScrollGeometryAction(
                        sample: FeedScrollChromeDebugSample(
                            normalizedOffsetY: sample.normalizedOffsetY,
                            rawOffsetY: sample.rawOffsetY,
                            contentInsetTop: sample.contentInsetTop,
                            contentHeight: 0,
                            containerHeight: 0
                        ),
                        trackerHidden: result.hidden,
                        visibilityChanged: result.changed,
                        scrollListenerActive: isActive,
                        surface: debugSurface
                    )
                    #endif
                }
        } else {
            content
                #if DEBUG
                .onAppear {
                    FeedScrollAwareHeaderDiagnostics.logScrollListenerAttached(
                        isActive: false,
                        surface: "\(debugSurface).inactive"
                    )
                }
                #endif
        }
    }

    @discardableResult
    private func applyScrollSample(sample: FeedScrollChromeGeometrySample) -> (changed: Bool, hidden: Bool) {
        applyScrollSample(
            normalizedOffsetY: sample.normalizedOffsetY,
            rawOffsetY: sample.rawOffsetY,
            contentInsetTop: sample.contentInsetTop
        )
    }

    @discardableResult
    private func applyScrollSample(
        normalizedOffsetY: CGFloat,
        rawOffsetY: CGFloat,
        contentInsetTop: CGFloat
    ) -> (changed: Bool, hidden: Bool) {
        var next = tracker
        let changed = next.apply(
            normalizedOffsetY: normalizedOffsetY,
            rawOffsetY: rawOffsetY,
            contentInsetTop: contentInsetTop,
            mode: trackingMode
        )
        tracker = next
        guard changed else { return (false, next.isChromeHidden) }
        applyChromeHidden(next.isChromeHidden)
        return (true, next.isChromeHidden)
    }

    private func applyChromeHidden(_ hidden: Bool) {
        if reduceMotion {
            chromeHidden = hidden
        } else {
            withAnimation(FeedScrollAwareHeaderExperiment.animation) {
                chromeHidden = hidden
            }
        }
    }
}
