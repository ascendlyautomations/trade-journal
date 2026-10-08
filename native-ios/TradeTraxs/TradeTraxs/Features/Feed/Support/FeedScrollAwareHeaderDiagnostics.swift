#if DEBUG
import Foundation
import os
import SwiftUI
import UIKit

/// Temporary runtime probe for Feed scroll-aware header experiment (DEBUG builds only).
enum FeedScrollAwareHeaderDiagnostics {
    private static let log = Logger(subsystem: AppLog.subsystem, category: "FeedScrollChrome")

    private static var geometryActionCount: Int = 0
    private static var uiKitSampleCount: Int = 0
    private static var lastLoggedNormalizedY: CGFloat?
    private static var lastLoggedAt: Date?
    private static var lastChromeHidden: Bool?

    static func logBootConfiguration() {
        log.info(
            """
            boot feedEnabled=\(FeedScrollAwareHeaderExperiment.isEnabled, privacy: .public) \
            dashboardEnabled=\(FeedScrollAwareHeaderExperiment.dashboardScrollHeaderEnabled, privacy: .public) \
            threshold=\(FeedScrollAwareHeaderExperiment.directionThreshold, privacy: .public) \
            categoryClearance=\(FeedScrollAwareHeaderExperiment.categoryBarClearance, privacy: .public)
            """
        )
    }

    static func logFeedHomeContext(
        surface: String,
        phase: String,
        contentFilter: String,
        feedPathDepth: Int,
        tabIsActive: Bool,
        experimentActive: Bool,
        entryCount: Int,
        visibleEntryCount: Int,
        chromeHidden: Bool
    ) {
        log.info(
            """
            context surface=\(surface, privacy: .public) phase=\(phase, privacy: .public) \
            filter=\(contentFilter, privacy: .public) feedPathDepth=\(feedPathDepth, privacy: .public) \
            tabActive=\(tabIsActive, privacy: .public) experimentActive=\(experimentActive, privacy: .public) \
            entries=\(entryCount, privacy: .public) visible=\(visibleEntryCount, privacy: .public) \
            chromeHidden=\(chromeHidden, privacy: .public)
            """
        )
    }

    static func logExperimentGateChange(
        experimentActive: Bool,
        isEnabled: Bool,
        isClips: Bool,
        feedPathDepth: Int
    ) {
        log.notice(
            """
            gate experimentActive=\(experimentActive, privacy: .public) \
            isEnabled=\(isEnabled, privacy: .public) isClips=\(isClips, privacy: .public) \
            feedPathDepth=\(feedPathDepth, privacy: .public)
            """
        )
    }

    static func logScrollListenerAttached(isActive: Bool, surface: String) {
        log.info(
            "scrollListener surface=\(surface, privacy: .public) isActive=\(isActive, privacy: .public)"
        )
    }

    static func logScrollGeometryAction(
        sample: FeedScrollChromeDebugSample,
        trackerHidden: Bool,
        visibilityChanged: Bool,
        scrollListenerActive: Bool,
        surface: String = "feed"
    ) {
        geometryActionCount += 1

        if visibilityChanged {
            log.notice(
                """
                chromeTransition surface=\(surface, privacy: .public) hidden=\(trackerHidden, privacy: .public) \
                normalizedY=\(sample.normalizedOffsetY, format: .fixed(precision: 2), privacy: .public) \
                rawY=\(sample.rawOffsetY, format: .fixed(precision: 2), privacy: .public) \
                insetTop=\(sample.contentInsetTop, format: .fixed(precision: 2), privacy: .public) \
                listenerActive=\(scrollListenerActive, privacy: .public) \
                geometryActions=\(geometryActionCount, privacy: .public)
                """
            )
            lastLoggedNormalizedY = sample.normalizedOffsetY
            lastLoggedAt = Date()
            return
        }

        let now = Date()
        let deltaY: CGFloat = {
            guard let lastLoggedNormalizedY else { return .greatestFiniteMagnitude }
            return abs(sample.normalizedOffsetY - lastLoggedNormalizedY)
        }()
        let elapsed = lastLoggedAt.map { now.timeIntervalSince($0) } ?? .greatestFiniteMagnitude

        guard deltaY >= 24 || elapsed >= 0.75 || geometryActionCount <= 3 else { return }

        lastLoggedNormalizedY = sample.normalizedOffsetY
        lastLoggedAt = now

        let scrollable = sample.contentHeight > sample.containerHeight + 1
        log.debug(
            """
            scrollSample surface=\(surface, privacy: .public) normalizedY=\(sample.normalizedOffsetY, format: .fixed(precision: 2), privacy: .public) \
            rawY=\(sample.rawOffsetY, format: .fixed(precision: 2), privacy: .public) \
            insetTop=\(sample.contentInsetTop, format: .fixed(precision: 2), privacy: .public) \
            contentH=\(sample.contentHeight, format: .fixed(precision: 2), privacy: .public) \
            containerH=\(sample.containerHeight, format: .fixed(precision: 2), privacy: .public) \
            scrollable=\(scrollable, privacy: .public) trackerHidden=\(trackerHidden, privacy: .public) \
            actions=\(geometryActionCount, privacy: .public)
            """
        )
    }

    static func logChromeHiddenState(
        chromeHidden: Bool,
        experimentActive: Bool,
        navVisibility: String,
        categoryOverlayHidden: Bool
    ) {
        guard lastChromeHidden != chromeHidden else { return }
        lastChromeHidden = chromeHidden
        log.notice(
            """
            uiState chromeHidden=\(chromeHidden, privacy: .public) \
            experimentActive=\(experimentActive, privacy: .public) \
            nav=\(navVisibility, privacy: .public) \
            categoryOverlayHidden=\(categoryOverlayHidden, privacy: .public)
            """
        )
    }

    static func logUIKitScrollSample(
        label: String,
        scrollView: UIScrollView,
        source: String
    ) {
        uiKitSampleCount += 1
        let normalized = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        let scrollable = scrollView.contentSize.height > scrollView.bounds.height + 1

        let deltaY: CGFloat = {
            guard let lastLoggedNormalizedY else { return .greatestFiniteMagnitude }
            return abs(normalized - lastLoggedNormalizedY)
        }()
        guard uiKitSampleCount <= 3 || deltaY >= 24 else { return }

        lastLoggedNormalizedY = normalized
        lastLoggedAt = Date()

        log.debug(
            """
            uiKitScroll label=\(label, privacy: .public) source=\(source, privacy: .public) \
            normalizedY=\(normalized, format: .fixed(precision: 2), privacy: .public) \
            rawY=\(scrollView.contentOffset.y, format: .fixed(precision: 2), privacy: .public) \
            adjustedInsetTop=\(scrollView.adjustedContentInset.top, format: .fixed(precision: 2), privacy: .public) \
            contentH=\(scrollView.contentSize.height, format: .fixed(precision: 2), privacy: .public) \
            boundsH=\(scrollView.bounds.height, format: .fixed(precision: 2), privacy: .public) \
            scrollable=\(scrollable, privacy: .public)
            """
        )
    }

    static func logNoGeometryActionsWarning(surface: String, secondsVisible: TimeInterval) {
        guard geometryActionCount == 0 else { return }
        log.error(
            """
            noScrollGeometry surface=\(surface, privacy: .public) visibleFor=\(secondsVisible, format: .fixed(precision: 1), privacy: .public)s \
            geometryActions=\(geometryActionCount, privacy: .public) uiKitSamples=\(uiKitSampleCount, privacy: .public) \
            hint=onScrollGeometryChange may not be bound to the scrolling UIScrollView
            """
        )
    }
}

/// DEBUG-only geometry payload for throttled scroll logging.
struct FeedScrollChromeDebugSample: Equatable {
    var normalizedOffsetY: CGFloat
    var rawOffsetY: CGFloat
    var contentInsetTop: CGFloat
    var contentHeight: CGFloat
    var containerHeight: CGFloat
}

/// Observes the nearest / outermost UIScrollView to compare UIKit offsets with SwiftUI geometry.
struct FeedScrollChromeUIKitProbe: UIViewRepresentable {
    let label: String

    func makeCoordinator() -> Coordinator {
        Coordinator(label: label)
    }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        context.coordinator.label = label
        uiView.resolveScrollViewIfNeeded()
    }

    final class Coordinator: NSObject, FeedScrollChromeProbeViewDelegate {
        var label: String
        private var observation: NSKeyValueObservation?
        private weak var observedScrollView: UIScrollView?

        init(label: String) {
            self.label = label
        }

        func scrollViewDidResolve(_ scrollView: UIScrollView) {
            guard observedScrollView !== scrollView else { return }
            observation?.invalidate()
            observedScrollView = scrollView
            FeedScrollAwareHeaderDiagnostics.logUIKitScrollSample(
                label: label,
                scrollView: scrollView,
                source: "resolve"
            )
            let probeLabel = label
            observation = scrollView.observe(\.contentOffset, options: [.new]) { scrollView, _ in
                FeedScrollAwareHeaderDiagnostics.logUIKitScrollSample(
                    label: probeLabel,
                    scrollView: scrollView,
                    source: "kvo"
                )
            }
        }

        deinit {
            observation?.invalidate()
        }
    }
}

@MainActor
protocol FeedScrollChromeProbeViewDelegate: AnyObject {
    func scrollViewDidResolve(_ scrollView: UIScrollView)
}

final class ProbeView: UIView {
    weak var delegate: FeedScrollChromeProbeViewDelegate?
    private(set) weak var resolvedScrollView: UIScrollView?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        resolveScrollViewIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        resolveScrollViewIfNeeded()
    }

    func resolveScrollViewIfNeeded() {
        let found = findEnclosingScrollView() ?? findOutermostScrollView(in: superview)
        guard found !== resolvedScrollView else { return }
        resolvedScrollView = found
        if let found {
            delegate?.scrollViewDidResolve(found)
        }
    }

    private func findEnclosingScrollView() -> UIScrollView? {
        var current: UIView? = superview
        while let view = current {
            if let scrollView = view as? UIScrollView { return scrollView }
            current = view.superview
        }
        return nil
    }

    private func findOutermostScrollView(in root: UIView?) -> UIScrollView? {
        guard let root else { return nil }
        var scrollViews: [UIScrollView] = []
        collectScrollViews(in: root, into: &scrollViews, budget: 96)
        let outermost = scrollViews.filter { candidate in
            !scrollViews.contains { other in
                other !== candidate && candidate.isDescendant(of: other)
            }
        }
        return outermost.max { lhs, rhs in
            lhs.bounds.width * lhs.bounds.height < rhs.bounds.width * rhs.bounds.height
        }
    }

    private func collectScrollViews(in root: UIView, into list: inout [UIScrollView], budget: Int) {
        guard budget > 0 else { return }
        if let scrollView = root as? UIScrollView {
            list.append(scrollView)
        }
        var remaining = budget - 1
        for subview in root.subviews where remaining > 0 {
            collectScrollViews(in: subview, into: &list, budget: remaining)
            remaining -= 1
        }
    }
}
#endif
