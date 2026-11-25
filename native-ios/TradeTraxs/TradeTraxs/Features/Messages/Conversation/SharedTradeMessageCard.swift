import SwiftUI

/// Compact trade-share bubble chrome for DM and Trade Room messages.
struct SharedTradeMessageCard: View {
    let trade: Trade?
    let tradeID: TradeID
    var messageID: MessageID? = nil
    let imagePipeline: any ImagePipeline
    var isOutgoing: Bool
    var includesBackground: Bool = true
    var mediaLayoutWidth: CGFloat? = nil
    var accountProviderName: String? = nil

    @Environment(\.themeColors) private var colors

    var body: some View {
        SharedTradePreviewCard(
            trade: trade,
            tradeID: tradeID,
            imagePipeline: imagePipeline,
            style: .card(isOutgoing: isOutgoing),
            mediaLayoutWidth: mediaLayoutWidth,
            accountProviderName: accountProviderName
        )
        .padding(.horizontal, includesBackground ? ExperienceSpacing.sm + 2 : 0)
        .padding(.vertical, includesBackground ? ExperienceSpacing.sm : 0)
        .frame(
            maxWidth: includesBackground
                ? ConversationBubbleMediaLayout.sharedCardBubbleMaxWidth
                : .infinity,
            alignment: .leading
        )
        .background {
            if includesBackground {
                RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
                    .fill(isOutgoing ? colors.accent : colors.incomingMessageBubble)
            }
        }
        .accessibilityIdentifier("conversation.bubble.trade")
        .onAppear {
            #if DEBUG
            if let messageID {
                SharedContentTrace.cardRender(
                    messageID: messageID,
                    tradeID: tradeID,
                    tradeLoaded: trade != nil
                )
            }
            #endif
        }
    }
}