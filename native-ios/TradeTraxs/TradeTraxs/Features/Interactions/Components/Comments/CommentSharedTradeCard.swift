import SwiftUI

/// Compact trade preview in a comment row.
struct CommentSharedTradeCard: View {
    let trade: Trade?
    let tradeID: TradeID
    let imagePipeline: any ImagePipeline
    var onTap: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Button(action: onTap) {
            SharedTradePreviewCard(
                trade: trade,
                tradeID: tradeID,
                imagePipeline: imagePipeline,
                style: .card(isOutgoing: false),
                mediaLayoutWidth: SharedTradePreviewMetrics.maxCardWidth
            )
            .padding(.horizontal, ExperienceSpacing.sm)
            .padding(.vertical, ExperienceSpacing.xs)
            .background(
                colors.fillSecondary,
                in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                    .strokeBorder(colors.separator.opacity(0.35), lineWidth: 0.5)
            }
        }
        .buttonStyle(.experiencePlain)
        .frame(maxWidth: SharedTradePreviewMetrics.maxCardWidth, alignment: .leading)
        .accessibilityIdentifier("interaction.comment.sharedTrade.\(tradeID.rawValue)")
    }
}