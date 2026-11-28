import Foundation

/// Feed/profile hydration guards for achievement monetary fields (public amounts, not account privacy).
nonisolated enum AchievementHydrationSupport {
    /// True when the UI can show a headline/category-row monetary line.
    static func hasMonetaryPresentation(_ achievement: Achievement) -> Bool {
        AchievementDetailPresentation.primaryAmountDisplay(for: achievement) != nil
    }

    /// Payout achievements without a display line are incomplete embed/stub rows — hydrate from `achievements`.
    static func needsMonetaryHydration(_ achievement: Achievement) -> Bool {
        guard ProfilePayoutTotals.isPayout(achievement.kind) else { return false }
        return !hasMonetaryPresentation(achievement)
    }

    /// Minimal feed timeline fallback built from post row fields only (no achievement join payload).
    static func isTimelineEmbedFallback(_ achievement: Achievement) -> Bool {
        achievement.value == nil
            && (achievement.valueText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            && achievement.description == nil
            && achievement.firm == nil
            && achievement.accountID == nil
            && achievement.tier == .bronze
            && achievement.sortOrder == 0
            && achievement.kind == .milestone
    }

    /// Feed/network should fetch `achievements` when RPC seed or embed fallback omitted monetary fields.
    static func needsFeedRowHydration(_ achievement: Achievement) -> Bool {
        if hasMonetaryPresentation(achievement) { return false }
        return needsMonetaryHydration(achievement) || isTimelineEmbedFallback(achievement)
    }
}