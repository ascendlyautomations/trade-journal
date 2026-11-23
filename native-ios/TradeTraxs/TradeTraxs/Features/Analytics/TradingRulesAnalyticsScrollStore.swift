import SwiftUI

/// Retains Trading Rules Analytics list offset across pushed detail routes (Feed parity).
@MainActor
enum TradingRulesAnalyticsScrollStore {
    private static var anchor: FeedListScrollAnchor?
    private static var retainedOffset: CGFloat?

    static func sharedAnchor() -> FeedListScrollAnchor {
        if let anchor { return anchor }
        let created = FeedListScrollAnchor(restoredOffset: retainedOffset)
        anchor = created
        if let retainedOffset, retainedOffset > 0.5 {
            created.applyRetainedOffset(retainedOffset)
        }
        return created
    }

    static func remember(_ offset: CGFloat) {
        guard offset > 0.5 else { return }
        retainedOffset = offset
    }

    static func restore() {
        guard let offset = retainedOffset, offset > 0.5 else { return }
        let anchor = sharedAnchor()
        anchor.applyRetainedOffset(offset)
        anchor.scheduleLayoutStableRestore()
    }

    static func resetForFreshNavigation() {
        retainedOffset = nil
        sharedAnchor().resetToTop()
    }

    static func clearRetainedOffset() {
        retainedOffset = nil
    }
}