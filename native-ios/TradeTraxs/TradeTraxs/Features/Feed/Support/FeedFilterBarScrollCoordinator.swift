import Foundation
import Observation

/// Blocks feed filter tour measurement until the pinned bar has a real post-layout frame.
@MainActor
enum FeedFilterBarTourLayoutGate {
    private(set) static var mayMeasure = false

    static func resetForTourStep() {
        mayMeasure = false
    }

    static func markLaidOut() {
        mayMeasure = true
    }

    static func clear() {
        mayMeasure = false
    }
}

/// Auto-hide state for the feed horizontal content-filter strip (All / Trades / …).
///
/// Driven by ``FeedHomeView`` scroll geometry — not used in Clips pager mode.
@Observable
@MainActor
final class FeedFilterBarScrollCoordinator {
    private(set) var isVisible: Bool = true

    static let revealUpThreshold: CGFloat = 70
    static let hideDownThreshold: CGFloat = 24
    static let jitterThreshold: CGFloat = 2.5
    static let atTopThreshold: CGFloat = 10

    private var lastOffsetY: CGFloat?
    private var cumulativeUp: CGFloat = 0
    private var cumulativeDown: CGFloat = 0
    private var trackingEnabled = true
    private(set) var walkthroughPinned = false

    /// Walkthrough pins the bar visible and pauses auto-hide until the step completes.
    func setWalkthroughPinned(_ pinned: Bool) {
        guard walkthroughPinned != pinned else { return }
        walkthroughPinned = pinned
        if pinned {
            revealAtTop()
        }
    }

    var isEffectivelyVisible: Bool {
        walkthroughPinned || isVisible
    }

    func setTrackingEnabled(_ enabled: Bool) {
        guard trackingEnabled != enabled else { return }
        trackingEnabled = enabled
        if enabled {
            resetCumulative()
        } else {
            revealAtTop()
        }
    }

    /// Tab reselect, filter change, or scroll returned to top.
    func revealAtTop() {
        resetCumulative()
        lastOffsetY = 0
        isVisible = true
    }

    func processContentOffset(_ y: CGFloat) {
        guard trackingEnabled, !walkthroughPinned else { return }

        if y <= Self.atTopThreshold {
            if !isVisible {
                isVisible = true
            }
            resetCumulative()
            lastOffsetY = y
            return
        }

        // Ignore rubber-band / overscroll so we do not flip visibility at the top edge.
        if y < 0 {
            lastOffsetY = y
            return
        }

        guard let last = lastOffsetY else {
            lastOffsetY = y
            return
        }

        let delta = y - last
        guard abs(delta) >= Self.jitterThreshold else { return }

        if delta > 0 {
            cumulativeDown += delta
            cumulativeUp = 0
            if isVisible, cumulativeDown >= Self.hideDownThreshold {
                setVisible(false)
                cumulativeDown = 0
            }
        } else {
            let upDistance = -delta
            cumulativeUp += upDistance
            cumulativeDown = 0
            if !isVisible, cumulativeUp >= Self.revealUpThreshold {
                setVisible(true)
                cumulativeUp = 0
            }
        }

        lastOffsetY = y
    }

    private func setVisible(_ visible: Bool) {
        guard isVisible != visible else { return }
        isVisible = visible
    }

    private func resetCumulative() {
        cumulativeUp = 0
        cumulativeDown = 0
    }
}