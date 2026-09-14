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
    enum LayoutStyle: Sendable {
        /// Feed / detail — horizontal scroll when chips overflow.
        case horizontalScroll
        /// Profile compact cards — wrap onto additional lines within available width.
        case wrap
    }

    let trade: Trade
    var showsQuantity: Bool = true
    var showsSession: Bool = true
    var layout: LayoutStyle = .horizontalScroll

    var body: some View {
        switch layout {
        case .horizontalScroll:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PublicTradeMetaChipRowLayout.chipSpacing) {
                    chipContent
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        case .wrap:
            ExperienceFlowLayout(
                spacing: PublicTradeMetaChipRowLayout.chipSpacing,
                rowSpacing: PublicTradeMetaChipRowLayout.chipSpacing
            ) {
                chipContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var chipContent: some View {
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
        if let duration = TradeDisplay.cardDurationText(for: trade) {
            PublicTradeMetaChip(title: duration, tone: .info)
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

private enum PublicTradeMetaChipRowLayout {
    static let chipSpacing: CGFloat = 3
    static let chipHorizontalPadding: CGFloat = 4
    static let chipVerticalPadding: CGFloat = 2
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
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, PublicTradeMetaChipRowLayout.chipHorizontalPadding)
            .padding(.vertical, PublicTradeMetaChipRowLayout.chipVerticalPadding)
            .background(toneColor.opacity(ExperienceOpacity.subtle))
            .clipShape(Capsule())
            .experienceAccessibility(label: title, identifier: "tag.\(title)")
    }
}
