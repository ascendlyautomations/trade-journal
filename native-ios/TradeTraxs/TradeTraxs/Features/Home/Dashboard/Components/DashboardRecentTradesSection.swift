import SwiftUI

/// Recent trades using the existing ``ProfileTradeCard``.
struct DashboardRecentTradesSection: View {
    let trades: [Trade]
    let accountNames: [TradingAccountID: String]
    let imagePipeline: any ImagePipeline
    let engagementStore: EngagementStore
    let onOpen: (Trade) -> Void
    let onSeeAll: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack {
                Text("Recent Trades")
                    .experienceStyle(.subheadline, color: colors.primaryText)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: onSeeAll) {
                    Text("See All")
                        .experienceStyle(.footnote, color: colors.accent)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dashboard.trades.seeAll")
            }
            .padding(.horizontal, ExperienceSpacing.md)

            if trades.isEmpty {
                Text("No trades in this range.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .padding(.horizontal, ExperienceSpacing.md)
            } else {
                LazyVStack(spacing: ExperienceSpacing.sm) {
                    ForEach(trades) { trade in
                        ProfileTradeCard(
                            trade: trade,
                            accountName: trade.accountID.flatMap { accountNames[$0] },
                            imagePipeline: imagePipeline,
                            engagementStore: engagementStore,
                            showsOwnerActions: false,
                            onOpen: { onOpen(trade) },
                            onShare: {},
                            onEdit: {},
                            onDelete: {}
                        )
                        .padding(.horizontal, ExperienceSpacing.md)
                    }
                }
            }
        }
        .accessibilityIdentifier("dashboard.recentTrades")
    }
}
