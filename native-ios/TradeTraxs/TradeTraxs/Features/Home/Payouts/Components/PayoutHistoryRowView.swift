import SwiftUI

struct PayoutHistoryRowView: View {
    let item: PayoutHistoryItem
    let account: TradingAccount?
    var showsPostedAsAchievement: Bool = false

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.xs) {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                Text(amountText)
                    .font(.system(.headline, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(colors.profit)

                Text(accountContextLine)
                    .font(.system(.subheadline, design: .default))
                    .foregroundStyle(colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: ExperienceSpacing.xs) {
                    Text(TradeDisplay.dateText(item.date))
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(colors.secondaryText)
                    if let status = statusLabel {
                        Text(status)
                            .font(.system(.caption2, design: .default).weight(.semibold))
                            .foregroundStyle(colors.secondaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(colors.fillSecondary.opacity(0.85))
                                    .overlay {
                                        Capsule(style: .continuous)
                                            .strokeBorder(colors.border.opacity(0.45), lineWidth: ExperienceBorder.hairline)
                                    }
                            }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(colors.tertiaryText)
        }
        .padding(.horizontal, ExperienceSpacing.sm)
        .padding(.vertical, ExperienceSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("withdrawals.history.\(item.id)")
    }

    private var amountText: String {
        ProfileDisplay.formatMoney(item.amount)
    }

    /// `Name · Mode`, authoritative mode, no inferred prop-firm labels.
    private var accountContextLine: String {
        guard let account else {
            let title = item.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return title.isEmpty ? "Payout" : title
        }
        let trimmedName = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let mode = TradingAccountDisplay.ownerDropdownModeLabel(account.mode)
        if trimmedName.isEmpty {
            return mode
        }
        return "\(trimmedName)\(TradingAccountDisplay.ownerDropdownSeparator)\(mode)"
    }

    private var statusLabel: String? {
        if showsPostedAsAchievement {
            return "Posted"
        }
        switch item.source {
        case .fundedCycle:
            return "Prop payout"
        case .liveLedger:
            return "Live"
        case .otherLedger:
            return "Recorded"
        case .achievementProp, .achievementLive:
            return "Achievement"
        }
    }
}