import SwiftUI

/// Bounded recent-trade picker reused by Create flows that need a trade reference.
struct TradePickerView: View {
    let trades: [Trade]
    var isLoading: Bool
    var title: String = "Link Trade"
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
                    title: "No trades yet",
                    message: "Log a trade first, then link it here."
                )
            } else {
                List(trades) { trade in
                    Button {
                        onSelect(trade)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(trade.symbol.ticker) · \(trade.side.rawValue.capitalized)")
                                .experienceStyle(.headline, color: colors.primaryText)
                            HStack(spacing: ExperienceSpacing.sm) {
                                if let pnl = trade.realizedPnL {
                                    Text(pnl.amount >= 0 ? "+\(pnl.amount)" : "\(pnl.amount)")
                                        .experienceStyle(
                                            .subheadline,
                                            color: pnl.amount >= 0 ? colors.profit : colors.loss
                                        )
                                }
                                Text(trade.entryAt, style: .date)
                                    .experienceStyle(.caption, color: colors.tertiaryText)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .accessibilityIdentifier("create.tradePicker.\(trade.id.rawValue)")
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
        .accessibilityIdentifier("create.tradePicker")
    }
}
