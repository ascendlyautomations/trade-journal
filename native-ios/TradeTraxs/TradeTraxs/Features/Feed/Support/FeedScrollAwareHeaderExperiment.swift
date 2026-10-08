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
           let previousInset = lastContentInsetTop,
           abs(rawOffsetY - previousRaw) < 1,
           abs(contentInsetTop - previousInset) > 8 {
            lastRawOffsetY = rawOffsetY
            lastContentInsetTop = contentInsetTop
            return false
        }

        let offsetY: CGFloat
        switch mode {
        case .timelineNormalized:
            offsetY = normalizedOffsetY
        case .navigationBarInsetStable, .dashboardNavigationBar:
            if !isChromeHidden {
                referenceContentInsetTop = contentInsetTop
            }
            let referenceInset = referenceContentInsetTop ?? contentInsetTop
            offsetY = rawOffsetY + referenceInset
            lastRawOffsetY = rawOffsetY
            lastContentInsetTop = contentInsetTop
        }

        if offsetY <= FeedScrollAwareHeaderExperiment.topRevealOffsetY {
            accumulatedDelta = 0
            lastOffsetY = offsetY
            guard isChromeHidden else { return false }
            isChromeHidden = false
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
            return true
        }

        if accumulatedDelta <= -threshold {
            accumulatedDelta = 0
            guard isChromeHidden else { return false }
            isChromeHidden = false
            return true
        }

        return false
    }
}
