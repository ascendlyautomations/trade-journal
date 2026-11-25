import SwiftUI

/// Compact trade attachment in livestream chat (uses shared preview chrome).
struct BroadcastChatCompactTradeCard: View {
    let trade: Trade?
    let tradeID: TradeID
    var loadFailed: Bool = false
    let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors

    var body: some View {
        SharedTradePreviewCard(
            trade: trade,
            tradeID: tradeID,
            imagePipeline: imagePipeline,
            style: .card(isOutgoing: false),
            loadFailed: loadFailed,
            mediaLayoutWidth: BroadcastChatAttachmentPolicy.chatTradeScreenshotLayoutWidth,
            screenshotUsesAspectFit: true
        )
        .padding(.horizontal, ExperienceSpacing.sm)
        .padding(.vertical, ExperienceSpacing.xs)
        .frame(
            maxWidth: SharedTradePreviewMetrics.maxCardWidth,
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
    }
}