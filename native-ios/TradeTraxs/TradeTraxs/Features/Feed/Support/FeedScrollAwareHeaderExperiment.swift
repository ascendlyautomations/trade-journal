import SwiftUI

/// Scroll-aware top chrome (Feed category strip, Dashboard filter bar, inline nav).
enum FeedScrollAwareHeaderExperiment {
    static let isEnabled = true
    static let dashboardScrollHeaderEnabled = true
    static let directionThreshold: CGFloat = 12
    static let topRevealOffsetY: CGFloat = 6
    static let animation = Animation.easeInOut(duration: 0.22)

    /// Fixed clearance matching ``FeedHomeView/contentFilterBar`` — stable scroll padding (inset never collapses).
    static let categoryBarClearance: CGFloat = ExperienceSpacing.sm + 6 + 52

}

/// How scroll samples map to tracker coordinates (Feed vs Dashboard nav-only chrome).
enum FeedScrollAwareHeaderTrackingMode {
    /// Navigation bar hide/show changes top inset; track with stable raw offset + reference inset.
    case navigationBarInsetStable
    /// Legacy alias — do not use normalized-only tracking when toggling toolbar visibility (Release loop).
    case timelineNormalized
    case dashboardNavigationBar

    var usesInsetStableNavigationTracking: Bool {
        switch self {
        case .navigationBarInsetStable, .dashboardNavigationBar:
            return true
        case .timelineNormalized:
            return false
        }
    }
}

/// Scroll geometry sample for `onScrollGeometryChange` (Debug and Release must match).
struct FeedScrollChromeGeometrySample: Equatable {
    var normalizedOffsetY: CGFloat
    var rawOffsetY: CGFloat
    var contentInsetTop: CGFloat
    var contentHeight: CGFloat
    var containerHeight: CGFloat

    /// Offset-driven equality only — layout-height flicker during nav chrome must not republish scroll actions.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.normalizedOffsetY == rhs.normalizedOffsetY
            && lhs.rawOffsetY == rhs.rawOffsetY
            && lhs.contentInsetTop == rhs.contentInsetTop
    }

    var hasValidScrollMetrics: Bool {
        contentHeight.isFinite
            && containerHeight.isFinite
            && containerHeight > 1
            && contentHeight > 0
    }
}

/// Interprets vertical scroll offset changes with hysteresis to avoid header flicker.
struct FeedScrollAwareHeaderTracker {
    private(set) var isChromeHidden = false
    private var lastOffsetY: CGFloat?
    private var accumulatedDelta: CGFloat = 0
    /// Last seen top inset while navigation chrome was visible (Dashboard nav-only tracking).
    private var referenceContentInsetTop: CGFloat?
    private var lastRawOffsetY: CGFloat?
    private var lastContentInsetTop: CGFloat?

    mutating func reset() {
        isChromeHidden = false
        lastOffsetY = nil
        accumulatedDelta = 0
        referenceContentInsetTop = nil
        lastRawOffsetY = nil
        lastContentInsetTop = nil
    }

    /// Returns `true` when visibility changed.
    mutating func apply(normalizedOffsetY: CGFloat) -> Bool {
        apply(
            normalizedOffsetY: normalizedOffsetY,
            rawOffsetY: normalizedOffsetY,
            contentInsetTop: 0,
            mode: .timelineNormalized
        )
    }

    /// Returns `true` when visibility changed.
    mutating func apply(
        normalizedOffsetY: CGFloat,
        rawOffsetY: CGFloat,
        contentInsetTop: CGFloat,
        mode: FeedScrollAwareHeaderTrackingMode
    ) -> Bool {
        if mode.usesInsetStableNavigationTracking,
           let previousRaw = lastRawOffsetY,
           let previousInset = lastContentInsetTop {
            let insetDelta = contentInsetTop - previousInset
            if abs(insetDelta) > 8 {
                let rawDelta = rawOffsetY - previousRaw
                // UIKit compensates contentOffset when navigation inset changes (Feed log: inset ±47, raw ∓47).
                if abs(rawDelta + insetDelta) < 6 {
                    lastRawOffsetY = rawOffsetY
                    lastContentInsetTop = contentInsetTop
                    if !isChromeHidden {
                        referenceContentInsetTop = contentInsetTop
                    }
                    lastOffsetY = trackingOffsetY(
                        normalizedOffsetY: normalizedOffsetY,
                        rawOffsetY: rawOffsetY,
                        contentInsetTop: contentInsetTop,
                        mode: mode
                    )
                    return false
                }
                if abs(rawOffsetY - previousRaw) < 1 {
                    lastRawOffsetY = rawOffsetY
                    lastContentInsetTop = contentInsetTop
                    return false
                }
            }
        }

        if mode.usesInsetStableNavigationTracking, !isChromeHidden {
            referenceContentInsetTop = contentInsetTop
        }

        let offsetY = trackingOffsetY(
            normalizedOffsetY: normalizedOffsetY,
            rawOffsetY: rawOffsetY,
            contentInsetTop: contentInsetTop,
            mode: mode
        )
        lastRawOffsetY = rawOffsetY
        lastContentInsetTop = contentInsetTop

        if offsetY <= FeedScrollAwareHeaderExperiment.topRevealOffsetY {
            accumulatedDelta = 0
            guard isChromeHidden else {
                lastOffsetY = offsetY
                return false
            }
            isChromeHidden = false
            syncScrollSampleAfterChromeVisibilityChange(
                normalizedOffsetY: normalizedOffsetY,
                rawOffsetY: rawOffsetY,
                contentInsetTop: contentInsetTop,
                mode: mode
            )
            return true
        }

        guard let previous = lastOffsetY else {
            lastOffsetY = offsetY
            return false
        }

        let delta = offsetY - previous
        lastOffsetY = offsetY

        guard abs(delta) > 0.5 else { return false }

        accumulatedDelta += delta
        let threshold = FeedScrollAwareHeaderExperiment.directionThreshold

        if accumulatedDelta >= threshold {
            accumulatedDelta = 0
            guard !isChromeHidden else { return false }
            isChromeHidden = true
            syncScrollSampleAfterChromeVisibilityChange(
                normalizedOffsetY: normalizedOffsetY,
                rawOffsetY: rawOffsetY,
                contentInsetTop: contentInsetTop,
                mode: mode
            )
            return true
        }

        if accumulatedDelta <= -threshold {
            accumulatedDelta = 0
            guard isChromeHidden else { return false }
            isChromeHidden = false
            syncScrollSampleAfterChromeVisibilityChange(
                normalizedOffsetY: normalizedOffsetY,
                rawOffsetY: rawOffsetY,
                contentInsetTop: contentInsetTop,
                mode: mode
            )
            return true
        }

        return false
    }

    /// Re-anchor after toolbar show/hide so the next sample is not a layout-induced delta.
    private mutating func syncScrollSampleAfterChromeVisibilityChange(
        normalizedOffsetY: CGFloat,
        rawOffsetY: CGFloat,
        contentInsetTop: CGFloat,
        mode: FeedScrollAwareHeaderTrackingMode
    ) {
        if mode.usesInsetStableNavigationTracking, !isChromeHidden {
            referenceContentInsetTop = contentInsetTop
        }
        lastRawOffsetY = rawOffsetY
        lastContentInsetTop = contentInsetTop
        lastOffsetY = trackingOffsetY(
            normalizedOffsetY: normalizedOffsetY,
            rawOffsetY: rawOffsetY,
            contentInsetTop: contentInsetTop,
            mode: mode
        )
        accumulatedDelta = 0
    }

    /// Visible nav: raw + reference inset (ignore inset-only jumps). Hidden nav: normalized — inset is 0 and reference inset must not inflate offsetY.
    private func trackingOffsetY(
        normalizedOffsetY: CGFloat,
        rawOffsetY: CGFloat,
        contentInsetTop: CGFloat,
        mode: FeedScrollAwareHeaderTrackingMode
    ) -> CGFloat {
        switch mode {
        case .timelineNormalized:
            return normalizedOffsetY
        case .navigationBarInsetStable, .dashboardNavigationBar:
            if isChromeHidden {
                return normalizedOffsetY
            }
            let referenceInset = referenceContentInsetTop ?? contentInsetTop
            return rawOffsetY + referenceInset
        }
    }
}
