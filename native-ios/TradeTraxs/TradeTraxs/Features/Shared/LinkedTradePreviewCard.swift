import SwiftUI

/// Selected linked-trade card shown before publish/send — thumbnail + summary + actions.
struct LinkedTradePreviewCard: View {
    let trade: Trade
    let imagePipeline: any ImagePipeline
    var changeTitle: String = "Change Trade"
    var removeTitle: String = "Remove"
    var onChange: () -> Void
    var onRemove: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            TradePreviewThumbnail(
                trade: trade,
                imagePipeline: imagePipeline,
                size: .preview
            )

            HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.xs) {
                Text(TradeDisplay.tickerText(trade.symbol))
                    .font(ExperienceTypography.headline)
                    .foregroundStyle(colors.primaryText)
                    .lineLimit(1)
                Text("·")
                    .experienceStyle(.headline, color: colors.tertiaryText)
                Text(TradeDisplay.sideTitle(trade.side).uppercased())
                    .font(ExperienceTypography.headline)
                    .foregroundStyle(colors.primaryText)
                    .lineLimit(1)
            }

            Text(TradeDisplay.pnlText(trade.realizedPnL))
                .font(ExperienceTypography.headline.monospacedDigit())
                .foregroundStyle(
                    theme.metricColor(
                        for: NSDecimalNumber(decimal: trade.realizedPnL?.amount ?? 0).doubleValue
                    )
                )
                .lineLimit(1)

            Text(entryExitLine(for: trade))
                .experienceStyle(.subheadline, color: colors.secondaryText)
                .lineLimit(2)

            HStack(spacing: ExperienceSpacing.md) {
                Button(changeTitle, action: onChange)
                    .font(ExperienceTypography.subheadline.weight(.semibold))
                    .foregroundStyle(colors.accent)
                Button(removeTitle, role: .destructive, action: onRemove)
                    .font(ExperienceTypography.subheadline.weight(.semibold))
            }
            .padding(.top, ExperienceSpacing.xxs)
        }
        .padding(ExperienceSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            colors.surfaceSecondary,
            in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private func entryExitLine(for trade: Trade) -> String {
        "Entry \(TradeDisplay.priceText(trade.entryPrice)) → Exit \(TradeDisplay.priceText(trade.exitPrice))"
    }
}
