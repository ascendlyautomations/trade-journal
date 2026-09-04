import SwiftUI

/// Compact trade row for picker sheets — thumbnail + ticker/side, PnL, timestamp.
struct TradePickerRowView: View {
    let trade: Trade
    let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
            TradePreviewThumbnail(
                trade: trade,
                imagePipeline: imagePipeline,
                size: .compact
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(TradeDisplay.tickerText(trade.symbol)) · \(TradeDisplay.sideTitle(trade.side))")
                    .experienceStyle(.headline, color: colors.primaryText)
                    .lineLimit(1)

                Text(TradeDisplay.pnlText(trade.realizedPnL))
                    .experienceStyle(
                        .subheadline,
                        color: pnlColor(for: trade.realizedPnL)
                    )
                    .lineLimit(1)

                Text(TradeDisplay.dateTimeText(trade.entryAt))
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func pnlColor(for money: Money?) -> Color {
        guard let amount = money?.amount else { return colors.secondaryText }
        return amount >= 0 ? colors.profit : colors.loss
    }
}
