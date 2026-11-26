import SwiftUI

/// Staged trade attachment above the DM / Trade Room message composer (comments parity).
struct MessageComposerTradeStagingRow: View {
    let trade: Trade
    let imagePipeline: any ImagePipeline
    let onRemove: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.xs) {
            SharedTradePreviewCard(
                trade: trade,
                tradeID: trade.id,
                imagePipeline: imagePipeline,
                style: .composerStrip
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(colors.tertiaryText)
            }
            .buttonStyle(.experiencePlain)
            .accessibilityLabel("Remove attached trade")
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .accessibilityIdentifier("conversation.composer.stagedTrade")
    }
}