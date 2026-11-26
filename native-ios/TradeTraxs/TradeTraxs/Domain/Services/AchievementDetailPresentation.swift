import Foundation

/// Profile + achievement detail caption (no extra network).
nonisolated enum AchievementDetailPresentation {
    typealias MetadataRow = (label: String, value: String)

    /// Legacy row builder, date omitted (identity header shows achieved date).
    static func metadataRows(for achievement: Achievement) -> [MetadataRow] {
        var rows: [MetadataRow] = []
        rows.append(("Type", achievementKindDisplayName(achievement.kind)))

        if let firm = publicFirm(from: achievement) {
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
        if let firm = publicFirm(from: achievement) {
            parts.append(firm)
        }
        return parts.joined(separator: " · ")
    }

    static func achievementKindDisplayName(_ kind: AchievementKind) -> String {
        switch kind {
        case .propFirmPayout: return "Prop Firm Payout"
        case .liveTradingPayout: return "Live Trading Payout"
        case .passedEvaluation: return "Evaluation Passed"
        case .milestone: return "Milestone"
        }
    }

    /// Blue category line above achievement titles (feed + detail), e.g. `Prop Firm Payout - Apex`.
    static func categoryContextLine(for achievement: Achievement) -> String {
        let category = achievementKindDisplayName(achievement.kind)
        guard let association = categoryAssociationName(for: achievement) else {
            return category
        }
        return "\(category) - \(association)"
    }

    private static func categoryAssociationName(for achievement: Achievement) -> String? {
        publicFirmLabel(for: achievement)
    }

    /// Prop firm label safe for feed, profile, detail, pins, and messages (never account ids/numbers).
    static func publicFirmLabel(for achievement: Achievement) -> String? {
        sanitizedFirmDisplay(
            raw: achievement.firm,
            accountID: achievement.accountID,
            linkedAccountName: nil,
            kind: achievement.kind
        )
    }

    /// Normalize stored `firm` when mapping API rows (keeps `accountID` for internal linkage).
    static func sanitizedStoredFirm(
        raw: String?,
        accountID: TradingAccountID?,
        linkedAccountName: String?,
        kind: AchievementKind
    ) -> String? {
        sanitizedFirmDisplay(
            raw: raw,
            accountID: accountID,
            linkedAccountName: linkedAccountName,
            kind: kind
        )
    }

    private static func sanitizedFirmDisplay(
        raw: String?,
        accountID: TradingAccountID?,
        linkedAccountName: String?,
        kind: AchievementKind
    ) -> String? {
        guard shouldShowFirmAssociation(for: kind) else { return nil }
        guard let trimmed = trimmedFirm(raw) else { return nil }
        guard !isPrivateAccountIdentifier(trimmed, accountID: accountID) else { return nil }
        let accountName = linkedAccountName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !accountName.isEmpty,
           trimmed.compare(accountName, options: .caseInsensitive) == .orderedSame {
            return nil
        }
        return trimmed
    }

    private static func shouldShowFirmAssociation(for kind: AchievementKind) -> Bool {
        switch kind {
        case .propFirmPayout, .passedEvaluation:
            return true
        case .liveTradingPayout, .milestone:
            return false
        }
    }

    private static func isPrivateAccountIdentifier(_ value: String, accountID: TradingAccountID?) -> Bool {
        if let accountID, value.compare(accountID.rawValue, options: .caseInsensitive) == .orderedSame {
            return true
        }
        if UUID(uuidString: value) != nil {
            return true
        }
        let lower = value.lowercased()
        if lower == "account" {
            return true
        }
        if value.range(of: #"^[0-9]{4,}$"#, options: .regularExpression) != nil {
            return true
        }
        if PublicAccountPrivacy.nameEmbedsAccountNumber(name: value, accountNumber: value) {
            return true
        }
        return false
    }

    private static func publicFirm(from achievement: Achievement) -> String? {
        publicFirmLabel(for: achievement)
    }

    private static func trimmedFirm(_ firm: String?) -> String? {
        let trimmed = firm?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func firmRowLabel(for kind: AchievementKind) -> String {
        switch kind {
        case .propFirmPayout, .passedEvaluation:
            return "Prop firm"
        case .liveTradingPayout, .milestone:
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

    /// Headline trailing amount (payout or milestone), nil when nothing to show on the right.
    static func headlineTrailingAmount(for achievement: Achievement) -> (text: String, usesMetricColor: Bool)? {
        primaryAmountDisplay(for: achievement)
    }

    /// Primary amount line below the title (feed + detail).
    static func primaryAmountDisplay(for achievement: Achievement) -> (text: String, usesMetricColor: Bool)? {
        if ProfilePayoutTotals.isPayout(achievement.kind),
           let payoutText = ProfilePayoutTotals.payoutDisplayText(for: achievement)
        {
            return (payoutText, true)
        }
        if let accessory = titleTrailingAccessory(for: achievement) {
            return (accessory, trailingAccessoryUsesMetricColor(for: achievement))
        }
        return nil
    }

    /// Chip labels for achievement type and account/firm (feed + detail meta row).
    static func metaChipTitles(for achievement: Achievement) -> [String] {
        var chips = [achievementKindDisplayName(achievement.kind)]
        if let firm = publicFirm(from: achievement) {
            chips.append(firm)
        }
        return chips
    }
}
