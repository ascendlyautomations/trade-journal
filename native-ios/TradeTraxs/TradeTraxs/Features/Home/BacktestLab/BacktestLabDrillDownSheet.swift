import SwiftUI

struct BacktestLabDrillDownSheet: View {
    let title: String
    let items: [TradeOwnerJournalSummary]
    let imagePipeline: any ImagePipeline
    let accountName: (TradingAccountID?) -> String?
    var onSelect: (TradeOwnerJournalSummary) -> Void
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ExperienceEmptyState(
                        icon: .chart,
                        title: "No matching trades",
                        message: "Try a wider time range or different filters."
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: ExperienceSpacing.sm) {
                            ForEach(items) { item in
                                TradeJournalCard(
                                    item: item,
                                    accountName: accountName(item.accountID),
                                    imagePipeline: imagePipeline,
                                    onOpen: { onSelect(item) }
                                )
                            }
                        }
                        .padding(.horizontal, ExperienceSpacing.md)
                        .padding(.vertical, ExperienceSpacing.sm)
                    }
                }
            }
            .experienceScreenBackground(usesGroupedFillInLightMode: true)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
    }
}