import SwiftUI

struct PayoutHistoryRowView: View {
    let item: PayoutHistoryItem
    let account: TradingAccount?

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(amountText)
                .font(.system(.body, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(colors.primaryText)
            Text(accountContextLine)
                .experienceStyle(.footnote, color: colors.secondaryText)
                .lineLimit(2)
            Text(TradeDisplay.dateText(item.date))
                .experienceStyle(.caption, color: colors.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, ExperienceSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("withdrawals.history.\(item.id)")
    }

    private var amountText: String {
        ProfileDisplay.formatMoney(item.amount)
    }

    /// `Name · Mode` — authoritative mode, no inferred prop-firm labels.
    private var accountContextLine: String {
        guard let account else { return "Account" }
        let trimmedName = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let mode = TradingAccountDisplay.ownerDropdownModeLabel(account.mode)
        if trimmedName.isEmpty {
            return mode
        }
        return "\(trimmedName)\(TradingAccountDisplay.ownerDropdownSeparator)\(mode)"
    }
}
