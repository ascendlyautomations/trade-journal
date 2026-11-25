import CoreGraphics

/// Width helpers for message-thread media (height comes from ``ImageFidelityTrace/displaySize``).
enum ConversationBubbleMediaLayout {
    static let sharedCardBubbleMaxWidth: CGFloat = SharedTradePreviewMetrics.maxCardWidth

    static func sharedCardMaxWidth(contentColumnMax: CGFloat) -> CGFloat {
        min(sharedCardBubbleMaxWidth, contentColumnMax)
    }

    static func photoMaxWidth(contentColumnMax: CGFloat, bubbleMaxWidth: CGFloat) -> CGFloat {
        min(bubbleMaxWidth, contentColumnMax)
    }

    /// Width available to inline heroes inside a shared bubble (after horizontal padding).
    static func sharedCardInnerWidth(outerMaxWidth: CGFloat, bubbleHorizontalPadding: CGFloat) -> CGFloat {
        max(1, outerMaxWidth - (2 * bubbleHorizontalPadding))
    }
}
