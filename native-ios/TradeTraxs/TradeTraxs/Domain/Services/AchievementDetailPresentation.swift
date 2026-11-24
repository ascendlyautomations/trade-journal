import Foundation

/// Profile + achievement detail caption (no extra network).
nonisolated enum AchievementDetailPresentation {
    typealias MetadataRow = (label: String, value: String)

    /// Legacy row builder, date omitted (identity header shows achieved date).
    static func metadataRows(for achievement: Achievement) -> [MetadataRow] {
        var rows: [MetadataRow] = []
        rows.append(("Type", achievementKindDisplayName(achievement.kind)))

        if let firm = trimmedFirm(achievement.firm) {
            let firmLabel = firmRowLabel(for: achievement.kind)
            rows.append((firmLabel, firm))
        }

        if let amount = milestoneOrAmountDisplay(for: achievement) {
            rows.append((amountRowLabel(for: achievement.kind), amount))
        }

        return rows
    }

    /// Trailing title accessory, milestone / evaluation (not used for payout headlines).
    static func titleTrailingAccessory(for achievement: Achievement) -> String? {
        guard !ProfilePayoutTotals.isPayout(achievement.kind) else { return nil }
        return milestoneOrAmountDisplay(for: achievement)
    }

    /// Compact caption under the description, type and firm when relevant.
    static func contextCaption(for achievement: Achievement) -> String? {
        var parts: [String] = [achievementKindDisplayName(achievement.kind)]
        if let firm = trimmedFirm(achievement.firm) {
            parts.append(firm)
        }
        return parts.joined(separator: " · ")
    }

    private static func achievementKindDisplayName(_ kind: AchievementKind) -> String {
        switch kind {
        case .propFirmPayout: return "Prop Firm Payout"
        case .liveTradingPayout: return "Live Trading Payout"
        case .passedEvaluation: return "Passed Eval"
        case .milestone: return "Milestone"
        }
    }

    private static func trimmedFirm(_ firm: String?) -> String? {
        let trimmed = firm?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func firmRowLabel(for kind: AchievementKind) -> String {
        switch kind {
        case .propFirmPayout, .passedEvaluation:
            return "Prop firm"
        case .liveTradingPayout:
            return "Account"
        case .milestone:
            return "Firm"
        }
    }

    private static func amountRowLabel(for kind: AchievementKind) -> String {
        switch kind {
        case .propFirmPayout, .liveTradingPayout:
            return "Payout amount"
        case .passedEvaluation:
            return "Evaluation"
        case .milestone:
            return "Milestone"
        }
    }

    /// Non-payout amounts / eval labels, payout headline carries payout totals.
    static func milestoneOrAmountDisplay(for achievement: Achievement) -> String? {
        if ProfilePayoutTotals.isPayout(achievement.kind) {
            return nil
        }
        if let value = achievement.value {
            return TradeDisplay.pnlText(value)
        }
        let trimmed = achievement.valueText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    static func trailingAccessoryUsesMetricColor(for achievement: Achievement) -> Bool {
        achievement.value != nil && !ProfilePayoutTotals.isPayout(achievement.kind)
    }
}
