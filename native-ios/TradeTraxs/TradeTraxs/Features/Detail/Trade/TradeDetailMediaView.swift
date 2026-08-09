import SwiftUI

/// Trade detail media — thin wrapper over shared ``AspectFitMediaView``.
struct TradeDetailMediaView: View {
    let reference: MediaReference?
    let imagePipeline: any ImagePipeline

    var body: some View {
        AspectFitMediaView(
            reference: reference,
            purpose: .tradeScreenshot,
            imagePipeline: imagePipeline,
            accessibilityIdentifier: "detail.trade.media",
            emptyIcon: .chart,
            allowsFullResolutionViewer: true
        )
    }
}
