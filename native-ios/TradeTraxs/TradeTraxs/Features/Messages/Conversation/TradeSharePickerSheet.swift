import SwiftUI

/// Presents the viewer's trades for sharing into a DM or Trade Room (web trade picker).
struct TradeSharePickerSheet: View {
    let trades: [Trade]
    let imagePipeline: any ImagePipeline
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
                            TradeSharePickerRow(trade: trade, imagePipeline: imagePipeline)
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

private struct TradeSharePickerRow: View {
    let trade: Trade
    let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors

    private let thumbnailSize: CGFloat = 60

    var body: some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
            TradeImageView(
                reference: ProfileCardMediaPresence.tradeMedia(in: trade),
                imagePipeline: imagePipeline,
                contentMode: .fill,
                side: thumbnailSize
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(trade.symbol.ticker) · \(TradeDisplay.sideTitle(trade.side))")
                    .experienceStyle(.headline, color: colors.primaryText)
                    .lineLimit(1)

                HStack(spacing: ExperienceSpacing.sm) {
                    Text(TradeDisplay.pnlText(trade.realizedPnL))
                        .experienceStyle(.subheadline, color: colors.secondaryText)
                        .lineLimit(1)
                    if trade.riskReward != nil {
                        Text(TradeDisplay.rrText(trade.riskReward))
                            .experienceStyle(.caption, color: colors.tertiaryText)
                            .lineLimit(1)
                    }
                }

                Text(TradeDisplay.dateTimeText(trade.entryAt))
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
