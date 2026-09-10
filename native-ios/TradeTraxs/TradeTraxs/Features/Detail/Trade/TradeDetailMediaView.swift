import SwiftUI

/// Trade detail media — inline interactive pinch zoom (no separate fullscreen viewer).
struct TradeDetailMediaView: View {
    let mediaID: String
    let reference: MediaReference?
    let imagePipeline: any ImagePipeline
    var onDoubleTapLike: (() -> Void)? = nil

    var body: some View {
        InteractiveImageView(
            mediaID: mediaID,
            reference: reference,
            purpose: .tradeScreenshot,
            imagePipeline: imagePipeline,
            emptyIcon: .chart,
            accessibilityIdentifier: "detail.trade.media",
            deliveryQuality: .fullResolution,
            auditSurface: "detail",
            onDoubleTapLike: onDoubleTapLike
        )
    }
}
