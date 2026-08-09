import SwiftUI

/// Rich trade-share card for DM and Trade Room bubbles (web trade message card).
struct SharedTradeMessageCard: View {
    let trade: Trade?
    let tradeID: TradeID
    var isOutgoing: Bool

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
                Text("\(trade.symbol.ticker) · \(trade.side.rawValue.uppercased())")
                    .experienceStyle(.headline, color: isOutgoing ? colors.onAccent : colors.primaryText)
                HStack(spacing: ExperienceSpacing.sm) {
                    if let pnl = trade.realizedPnL {
                        Text(formatMoney(pnl.amount))
                            .experienceStyle(.subheadline, color: isOutgoing ? colors.onAccent : colors.secondaryText)
                    }
                    if let rr = trade.riskReward {
                        Text("RR \(rr)")
                            .experienceStyle(.caption, color: isOutgoing ? colors.onAccent.opacity(0.85) : colors.tertiaryText)
                    }
                }
            } else {
                Text("Trade \(tradeID.rawValue.prefix(8))…")
                    .experienceStyle(.subheadline, color: isOutgoing ? colors.onAccent : colors.secondaryText)
            }
        }
        .padding(.horizontal, ExperienceSpacing.sm + 2)
        .padding(.vertical, ExperienceSpacing.sm)
        .frame(maxWidth: 260, alignment: .leading)
        .background(
            isOutgoing ? colors.accent : colors.incomingMessageBubble,
            in: RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
        )
        .accessibilityIdentifier("conversation.bubble.trade")
    }

    private func formatMoney(_ amount: Decimal) -> String {
        let number = NSDecimalNumber(decimal: amount)
        let prefix = amount >= 0 ? "+" : ""
        return "\(prefix)\(number.stringValue)"
    }
}
