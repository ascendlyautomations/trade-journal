import SwiftUI

/// Ticker + P&L headline row for public trade cards — matched size, weight, and baseline.
struct PublicTradeHeadlineRow: View {
    let ticker: String
    let realizedPnL: Money?

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.sm) {
            Text(ticker)
                .font(ExperienceTypography.headline)
                .foregroundStyle(colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .layoutPriority(1)

            Spacer(minLength: ExperienceSpacing.xs)

            Text(TradeDisplay.pnlText(realizedPnL))
                .font(ExperienceTypography.headline.monospacedDigit())
                .foregroundStyle(
                    theme.metricColor(
                        for: NSDecimalNumber(decimal: realizedPnL?.amount ?? 0).doubleValue
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Side, account-type, RR, quantity (and optional session) chips for public trade surfaces.
struct PublicTradeMetaChipRow: View {
    let trade: Trade
    var showsQuantity: Bool = true
    var showsSession: Bool = true

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ExperienceSpacing.xxs) {
                PublicTradeMetaChip(
                    title: TradeDisplay.sideTitle(trade.side),
                    tone: trade.side == .long ? .success : .error
                )
                if let accountBadge = trade.publicAccountBadge {
                    PublicTradeMetaChip(title: accountBadge, tone: .info)
                }
                if trade.riskReward != nil {
                    PublicTradeMetaChip(title: TradeDisplay.rrText(trade.riskReward), tone: .info)
                }
                if let points = TradeDisplay.pointsText(trade.points) {
                    PublicTradeMetaChip(title: "Pts \(points)", tone: .info)
                }
                if trade.mode == .copyTraded {
                    PublicTradeMetaChip(
                        title: TradeDisplay.tradeModeFallbackTitle(.copyTraded) ?? "Copy Traded",
                        tone: .info
                    )
                }
                if showsQuantity {
                    PublicTradeMetaChip(
                        title: TradeDisplay.quantityBadgeText(trade.quantity),
                        tone: .info
                    )
                }
                if showsSession,
                   let session = trade.sessionLabel?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !session.isEmpty
                {
                    PublicTradeMetaChip(title: session, tone: .info)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Compact intrinsic-width chip for public trade metadata rows.
private struct PublicTradeMetaChip: View {
    let title: String
    var tone: BannerTone = .info

    @Environment(\.themeColors) private var colors

    var body: some View {
        let toneColor = tone.color(in: colors)
        Text(title)
            .experienceStyle(.caption2, color: toneColor)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(toneColor.opacity(ExperienceOpacity.subtle))
            .clipShape(Capsule())
            .experienceAccessibility(label: title, identifier: "tag.\(title)")
    }
}
