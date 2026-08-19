import SwiftUI

/// Presents the viewer's trades for sharing into a DM or Trade Room (web trade picker).
struct TradeSharePickerSheet: View {
    let trades: [Trade]
    var isLoading: Bool
    var onSelect: (Trade) -> Void
    var onClose: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ExperienceLoadingSpinner(label: "Loading trades")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if trades.isEmpty {
                    ExperienceEmptyState(
                        icon: .trades,
                        title: "No trades to share",
                        message: "Log a trade first, then share it here."
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
                                        Text(pnl.amount as NSDecimalNumber as Decimal >= 0
                                            ? "+\(pnl.amount)"
                                            : "\(pnl.amount)")
                                            .experienceStyle(.subheadline, color: colors.secondaryText)
                                    }
                                    if let rr = trade.riskReward {
                                        Text("RR \(rr)")
                                            .experienceStyle(.caption, color: colors.tertiaryText)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .accessibilityIdentifier("conversation.tradePicker.\(trade.id.rawValue)")
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .experienceScreenBackground()
            .experienceNavigationTitle("Send Trade")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
        }
        .experienceSheetChrome()
        .accessibilityIdentifier("conversation.tradePicker")
    }
}
