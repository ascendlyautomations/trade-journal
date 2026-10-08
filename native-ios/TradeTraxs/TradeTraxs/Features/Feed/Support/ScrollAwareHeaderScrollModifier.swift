import SwiftUI

/// Shared scroll-geometry → header chrome hide/show (Feed timeline, Dashboard, …).
struct ScrollAwareHeaderScrollModifier: ViewModifier {
    let isActive: Bool
    let reduceMotion: Bool
    let debugSurface: String
    var trackingMode: FeedScrollAwareHeaderTrackingMode = .navigationBarInsetStable
    /// When false, only the binding updates; ancestor applies `.animation` (Feed host — avoids stacked `withAnimation`).
    var appliesChromeVisibilityAnimation = true
    @Binding var tracker: FeedScrollAwareHeaderTracker
    @Binding var chromeHidden: Bool

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: FeedScrollChromeGeometrySample.self) { geometry in
                FeedScrollChromeGeometrySample(
                    normalizedOffsetY: geometry.contentOffset.y + geometry.contentInsets.top,
                    rawOffsetY: geometry.contentOffset.y,
                    contentInsetTop: geometry.contentInsets.top,
                    contentHeight: geometry.contentSize.height,
                    containerHeight: geometry.containerSize.height
                )
            } action: { _, sample in
                guard isActive else { return }
                guard sample.hasValidScrollMetrics else { return }
                let result = applyScrollSample(sample: sample)
                #if DEBUG
                FeedScrollAwareHeaderDiagnostics.logScrollGeometryAction(
                    sample: FeedScrollChromeDebugSample(
                        normalizedOffsetY: sample.normalizedOffsetY,
                        rawOffsetY: sample.rawOffsetY,
                        contentInsetTop: sample.contentInsetTop,
                        contentHeight: sample.contentHeight,
                        containerHeight: sample.containerHeight
                    ),
                    trackerHidden: result.hidden,
                    visibilityChanged: result.changed,
                    scrollListenerActive: isActive,
                    surface: debugSurface
                )
                #endif
            }
            #if DEBUG
            .onAppear {
                FeedScrollAwareHeaderDiagnostics.logScrollListenerAttached(
                    isActive: isActive,
                    surface: debugSurface
                )
            }
            .onChange(of: isActive) { _, active in
                FeedScrollAwareHeaderDiagnostics.logScrollListenerAttached(
                    isActive: active,
                    surface: "\(debugSurface).gate"
                )
            }
            #endif
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
        if reduceMotion || !appliesChromeVisibilityAnimation {
            chromeHidden = hidden
        } else {
            withAnimation(FeedScrollAwareHeaderExperiment.animation) {
                chromeHidden = hidden
            }
        }
    }
}
