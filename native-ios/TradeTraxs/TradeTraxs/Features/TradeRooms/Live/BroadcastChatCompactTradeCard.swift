import SwiftUI

/// Livestream-only compact trade attachment — not the full DM trade share card.
struct BroadcastChatCompactTradeCard: View {
    let trade: Trade?
    let tradeID: TradeID
    var loadFailed: Bool = false
    let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    private let tickerFont = Font.system(size: 14.5, design: .rounded).weight(.semibold)
    private let pnlFont = Font.system(size: 15.5, design: .rounded).weight(.semibold).monospacedDigit()

    var body: some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.xs) {
            TradePreviewThumbnail(
                trade: trade,
                imagePipeline: imagePipeline,
                size: .livestreamChat
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                if let trade {
                    Text("\(TradeDisplay.tickerText(trade.symbol)) · \(TradeDisplay.sideTitle(trade.side).uppercased())")
                        .font(tickerFont)
                        .foregroundStyle(colors.primaryText)
                        .lineLimit(1)
                    Text(TradeDisplay.pnlText(trade.realizedPnL))
                        .font(pnlFont)
                        .foregroundStyle(pnlColor(for: trade.realizedPnL))
                        .lineLimit(1)
                } else if loadFailed {
                    Text("Shared trade")
                        .font(tickerFont)
                        .foregroundStyle(colors.primaryText)
                    Text("Trade unavailable")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(colors.error)
                        .lineLimit(2)
                } else {
                    Text("Shared trade")
                        .font(tickerFont)
                        .foregroundStyle(colors.primaryText)
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, ExperienceSpacing.sm)
        .padding(.vertical, ExperienceSpacing.xs)
        .frame(
            maxWidth: BroadcastChatAttachmentPolicy.chatTradeCardMaxWidth,
            minHeight: BroadcastChatAttachmentPolicy.chatTradeCardMinHeight,
            maxHeight: BroadcastChatAttachmentPolicy.chatTradeCardMaxHeight,
            alignment: .leading
        )
        .background(
            colors.fillSecondary,
            in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                .strokeBorder(colors.separator.opacity(0.35), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tradeAccessibilityLabel)
        .accessibilityHint("Opens trade details")
    }

    private var tradeAccessibilityLabel: String {
        if loadFailed, trade == nil { return "Shared trade unavailable" }
        guard let trade else { return "Shared trade loading" }
        return "\(TradeDisplay.tickerText(trade.symbol)), \(TradeDisplay.sideTitle(trade.side)), \(TradeDisplay.pnlText(trade.realizedPnL))"
    }

    private func pnlColor(for money: Money?) -> Color {
        guard let amount = money?.amount else { return colors.secondaryText }
        return theme.metricColor(for: NSDecimalNumber(decimal: amount).doubleValue)
    }
}