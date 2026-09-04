import SwiftUI

/// Bounded recent-trade picker reused by Create flows and DM/Room trade share.
struct TradePickerView: View {
    let trades: [Trade]
    let imagePipeline: any ImagePipeline
    var isLoading: Bool
    var title: String = "Link Trade"
    var emptyTitle: String = "No trades yet"
    var emptyMessage: String = "Log a trade first, then link it here."
    var onSelect: (Trade) -> Void
    var onClose: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading trades…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if trades.isEmpty {
                ExperienceEmptyState(
                    icon: .trades,
                    title: emptyTitle,
                    message: emptyMessage
                )
            } else {
                List(trades) { trade in
                    Button {
                        onSelect(trade)
                    } label: {
                        TradePickerRowView(trade: trade, imagePipeline: imagePipeline)
                    }
                    .accessibilityIdentifier(pickerAccessibilityID(for: trade))
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", action: onClose)
            }
        }
        .accessibilityIdentifier(rootAccessibilityIdentifier)
    }

    private var rootAccessibilityIdentifier: String {
        title == "Send Trade" ? "conversation.tradePicker" : "create.tradePicker"
    }

    private func pickerAccessibilityID(for trade: Trade) -> String {
        title == "Send Trade"
            ? "conversation.tradePicker.\(trade.id.rawValue)"
            : "create.tradePicker.\(trade.id.rawValue)"
    }
}
