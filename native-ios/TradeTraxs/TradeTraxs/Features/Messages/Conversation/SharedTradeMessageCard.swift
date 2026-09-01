import SwiftUI

/// Rich trade-share card for DM and Trade Room bubbles (web trade message card).
struct SharedTradeMessageCard: View {
    let trade: Trade?
    let tradeID: TradeID
    var isOutgoing: Bool
    var includesBackground: Bool = true

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.caption.weight(.semibold))
                Text("Shared trade")
                    .experienceStyle(.caption, color: isOutgoing ? colors.onAccent.opacity(0.85) : colors.tertiaryText)
            }
            if let trade {
                sharedTradeHeadline(trade)
                sharedTradeChips(trade)
            } else {
                Text("Trade \(tradeID.rawValue.prefix(8))…")
                    .experienceStyle(.subheadline, color: isOutgoing ? colors.onAccent : colors.secondaryText)
            }
        }
        .padding(.horizontal, includesBackground ? ExperienceSpacing.sm + 2 : 0)
        .padding(.vertical, includesBackground ? ExperienceSpacing.sm : 0)
        .frame(maxWidth: 260, alignment: .leading)
        .background {
            if includesBackground {
                RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
                    .fill(isOutgoing ? colors.accent : colors.incomingMessageBubble)
            }
        }
        .accessibilityIdentifier("conversation.bubble.trade")
    }

    @ViewBuilder
    private func sharedTradeHeadline(_ trade: Trade) -> some View {
        if isOutgoing {
            HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.xs) {
                Text(trade.symbol.ticker)
                    .font(ExperienceTypography.headline)
                    .foregroundStyle(colors.onAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .layoutPriority(1)
                Spacer(minLength: ExperienceSpacing.xxs)
                Text(TradeDisplay.pnlText(trade.realizedPnL))
                    .font(ExperienceTypography.headline.monospacedDigit())
                    .foregroundStyle(colors.onAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        } else {
            PublicTradeHeadlineRow(
                ticker: trade.symbol.ticker,
                realizedPnL: trade.realizedPnL
            )
        }
    }

    @ViewBuilder
    private func sharedTradeChips(_ trade: Trade) -> some View {
        HStack(spacing: ExperienceSpacing.xs) {
            Text(TradeDisplay.sideTitle(trade.side))
                .experienceStyle(
                    .caption2,
                    color: isOutgoing ? colors.onAccent.opacity(0.9) : colors.secondaryText
                )
            if let accountBadge = trade.publicAccountBadge {
                Text(accountBadge)
                    .experienceStyle(
                        .caption2,
                        color: isOutgoing ? colors.onAccent.opacity(0.9) : colors.secondaryText
                    )
            }
            if let rr = trade.riskReward {
                Text(TradeDisplay.rrText(rr))
                    .experienceStyle(
                        .caption,
                        color: isOutgoing ? colors.onAccent.opacity(0.85) : colors.tertiaryText
                    )
            }
        }
    }
}
