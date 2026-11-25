import SwiftUI

struct PayoutHistoryRowView: View {
    let item: PayoutHistoryItem
    let account: TradingAccount?
    var showsPostedAsAchievement: Bool = false

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                Text(amountText)
                    .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(colors.profit)

                Text(accountContextLine)
                    .experienceStyle(.subheadline, color: colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: ExperienceSpacing.sm) {
                    Text(TradeDisplay.dateText(item.date))
                        .experienceStyle(.caption, color: colors.secondaryText)
                    if let status = statusLabel {
                        Text(status)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(colors.secondaryText)
                            .padding(.horizontal, ExperienceSpacing.xs)
                            .padding(.vertical, 2)
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
                .font(.footnote.weight(.semibold))
                .foregroundStyle(colors.tertiaryText)
        }
        .padding(ExperienceSpacing.md)
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