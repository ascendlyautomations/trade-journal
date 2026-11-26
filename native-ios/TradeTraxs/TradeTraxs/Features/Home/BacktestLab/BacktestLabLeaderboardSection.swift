import SwiftUI

struct BacktestLabLeaderboardSection: View {
    let title: String
    let rows: [BacktestLabGroupRow]
    var onSelect: (BacktestLabGroupRow) -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text(title)
                .experienceStyle(.headline, color: colors.primaryText)

            if rows.isEmpty {
                Text("No trades in this filter.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .padding(.vertical, ExperienceSpacing.sm)
            } else {
                VStack(spacing: ExperienceSpacing.xs) {
                    ForEach(rows.prefix(8)) { row in
                        Button {
                            onSelect(row)
                        } label: {
                            rowContent(row)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceTradingRulesCard(prominence: .featured)
    }

    private func rowContent(_ row: BacktestLabGroupRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.label)
                    .experienceStyle(.subheadline, color: colors.primaryText)
                    .lineLimit(1)
                Text("\(row.tradeCount) trades · \(String(format: "%.0f%%", row.winRatePercent)) win")
                    .experienceStyle(.caption, color: colors.tertiaryText)
            }
            Spacer(minLength: ExperienceSpacing.xs)
            Text(TradeDisplay.pnlText(Money(amount: row.netPnL)))
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(row.netPnL >= 0 ? colors.profit : colors.loss)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, ExperienceSpacing.xxs)
        .contentShape(Rectangle())
    }
}