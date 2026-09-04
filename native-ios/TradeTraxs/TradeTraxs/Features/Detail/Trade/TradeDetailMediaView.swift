import SwiftUI

/// Trade detail media — compact inline preview; tap for full screen.
struct TradeDetailMediaView: View {
    let reference: MediaReference?
    let imagePipeline: any ImagePipeline
    var onDoubleTapLike: (() -> Void)? = nil

    var body: some View {
        AspectFitMediaView(
            reference: reference,
            purpose: .tradeScreenshot,
            imagePipeline: imagePipeline,
            accessibilityIdentifier: "detail.trade.media",
            emptyIcon: .chart,
            allowsFullResolutionViewer: true,
            maxDisplayHeightOverride: 200,
            onDoubleTapLike: onDoubleTapLike
        )
    }
}
