import SwiftUI

/// Shared trade screenshot thumbnail for pickers, linked-trade previews, and message cards.
///
/// Three visual states (via ``TradeImageView``):
/// - trade has image → aspect-filled thumbnail
/// - loading → skeleton
/// - missing / failed URL → compact chart placeholder (fixed slot size)
struct TradePreviewThumbnail: View {
    enum Size: Equatable {
        /// Picker rows — 60×60
        case compact
        /// Selected-trade preview — 88×88
        case preview
        /// Message-card hero — full width, capped height
        case messageHero(maxHeight: CGFloat? = nil)
    }

    let trade: Trade?
    let imagePipeline: any ImagePipeline
    var size: Size = .compact
    var layoutWidth: CGFloat? = nil
    /// Override when the caller already resolved media (e.g. hydrated message bubble).
    var referenceOverride: MediaReference?

    var body: some View {
        switch size {
        case .compact:
            tradeImageView(side: 60, contentMode: .fill)
        case .preview:
            tradeImageView(side: 88, contentMode: .fill)
        case .messageHero(let maxHeight):
            AspectFitMediaView(
                reference: resolvedReference,
                purpose: .tradeScreenshot,
                imagePipeline: imagePipeline,
                accessibilityIdentifier: "conversation.tradeHero",
                allowsFullResolutionViewer: false,
                maxDisplayHeightOverride: maxHeight,
                layoutWidth: layoutWidth
            )
        }
    }

    @ViewBuilder
    private func tradeImageView(
        side: CGFloat? = nil,
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        contentMode: ContentMode
    ) -> some View {
        TradeImageView(
            reference: resolvedReference,
            imagePipeline: imagePipeline,
            contentMode: contentMode,
            side: side ?? 60,
            width: width,
            height: height
        )
    }

    private var resolvedReference: MediaReference? {
        if let referenceOverride { return referenceOverride }
        guard let trade else { return nil }
        return ProfileCardMediaPresence.tradeMedia(in: trade)
    }
}
