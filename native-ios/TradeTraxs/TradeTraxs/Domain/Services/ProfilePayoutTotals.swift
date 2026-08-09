import Foundation

/// Mirrors web `sumPayoutAchievementTotals` (`lib/achievementTypes.ts`).
///
/// Sums `value_numeric` for prop-firm + live-trading payout achievements only.
nonisolated enum ProfilePayoutTotals {
    static func sum(from achievements: [Achievement]) -> Decimal {
        achievements.reduce(Decimal(0)) { partial, achievement in
            guard isPayout(achievement.kind) else { return partial }
            return partial + (achievement.value?.amount ?? 0)
        }
    }

    /// Web `isPayoutAchievementType` — prop firm, live trading, and legacy `payout`
    /// (mapped to ``AchievementKind/liveTradingPayout`` on read).
    static func isPayout(_ kind: AchievementKind) -> Bool {
        switch kind {
        case .propFirmPayout, .liveTradingPayout:
            return true
        case .passedEvaluation, .milestone:
            return false
        }
    }
}
