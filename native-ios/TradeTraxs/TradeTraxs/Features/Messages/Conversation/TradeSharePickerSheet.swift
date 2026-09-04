import SwiftUI

/// Presents the viewer's trades for sharing into a DM or Trade Room (web trade picker).
struct TradeSharePickerSheet: View {
    let trades: [Trade]
    let imagePipeline: any ImagePipeline
    var isLoading: Bool
    var onSelect: (Trade) -> Void
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            TradePickerView(
                trades: trades,
                imagePipeline: imagePipeline,
                isLoading: isLoading,
                title: "Send Trade",
                emptyTitle: "No trades to share",
                emptyMessage: "Log a trade first, then share it here.",
                onSelect: onSelect,
                onClose: onClose
            )
        }
        .experienceSheetChrome()
    }
}
