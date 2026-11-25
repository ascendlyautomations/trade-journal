import SwiftUI

struct TradingRulesRuleTradesSheet: View {
    let ruleLabel: String
    let outcomes: TradingRulesRuleTradeOutcomePresentation.GroupedOutcomes
    var onOpenTrade: (TradeID) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                    section(title: "Followed", rows: outcomes.followed, tone: colors.profit)
                    section(title: "Violated", rows: outcomes.violated, tone: colors.loss)
                }
                .padding(ExperienceSpacing.md)
            }
            .experienceScreenBackground()
            .experienceNavigationTitle(ruleLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .experienceSheetChrome()
        .accessibilityIdentifier("tradingRulesAnalytics.ruleTradesSheet")
    }

    @ViewBuilder
    private func section(title: String, rows: [TradingRulesRuleTradeOutcomePresentation.TradeRow], tone: Color) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack(spacing: ExperienceSpacing.xs) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colors.primaryText)
                Text("(\(rows.count))")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(tone)
            }

            if rows.isEmpty {
                Text("No trades in this group.")
                    .experienceStyle(.caption, color: colors.secondaryText)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        tradeRow(row, tone: tone)
                        if index < rows.count - 1 {
                            ExperienceDivider()
                        }
                    }
                }
                .experienceTradingRulesCard(prominence: .standard)
            }
        }
    }

    @ViewBuilder
    private func tradeRow(
        _ row: TradingRulesRuleTradeOutcomePresentation.TradeRow,
        tone: Color
    ) -> some View {
        Button {
            onOpenTrade(TradeID(row.tradeID))
            dismiss()
        } label: {
            HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
                Circle()
                    .fill(tone.opacity(0.85))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    if let net = row.netPnl {
                        Text(TradingRulesRuleImpactFormat.signedMoney(net))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(
                                net > 0 ? colors.profit : net < 0 ? colors.loss : colors.primaryText
                            )
                    } else {
                        Text("Trade")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(colors.primaryText)
                    }
                    if !row.detail.isEmpty {
                        Text(row.detail)
                            .experienceStyle(.caption2, color: colors.secondaryText)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: ExperienceSpacing.xs)
                Text(Self.dateFormatter.string(from: row.at))
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(colors.tertiaryText)
            }
            .padding(ExperienceSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}