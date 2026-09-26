import SwiftUI

/// Review reconstructed Tradovate trades (server P&L) before persisting to Supabase.
struct BrokerTradovateImportPreviewView: View {
    let trades: [TradovateImportPreviewTrade]
    let isConfirming: Bool
    var embedInParentNavigation = false
    let onConfirm: () async -> Void
    let onCancel: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Group {
            if embedInParentNavigation {
                previewList
            } else {
                NavigationStack {
                    previewList
                }
            }
        }
    }

    private var previewList: some View {
        List {
                Section {
                    Text("These trades were reconstructed from your broker fills. Dollar P&L is calculated on the server. After you import, you can add journal details on the next screen.")
                        .experienceStyle(.footnote, color: colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("Review Imported Trades") {
                    ForEach(trades) { trade in
                        tradeRow(trade)
                            .accessibilityIdentifier("brokerImport.preview.\(trade.lifecycleKey)")
                    }
                }
            }
        .listStyle(.insetGrouped)
        .experienceDashboardGroupedRows()
        .scrollContentBackground(.hidden)
        .experienceNavigationTitle(embedInParentNavigation ? "Confirm Import" : "Review Imported Trades")
        .toolbar {
            if !embedInParentNavigation {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .disabled(isConfirming)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ExperienceButton(
                title: "Import \(trades.count) Trade\(trades.count == 1 ? "" : "s")",
                kind: .primary,
                isEnabled: !trades.isEmpty,
                isLoading: isConfirming,
                accessibilityIdentifier: "brokerImport.preview.confirm"
            ) {
                Task { await onConfirm() }
            }
            .padding(ExperienceSpacing.md)
            .background(colors.backgroundPrimary.opacity(0.96))
        }
    }

    @ViewBuilder
    private func tradeRow(_ trade: TradovateImportPreviewTrade) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            HStack {
                Text(trade.ticker)
                    .experienceStyle(.headline, color: colors.primaryText)
                Text(trade.direction.uppercased())
                    .experienceStyle(.caption, color: colors.secondaryText)
                Spacer()
                Text(pnlLine(trade.pnl))
                    .experienceStyle(.subheadline, color: pnlColor(trade.pnl))
                    .fontWeight(.semibold)
            }

            Text("Entry: \(formatPrice(trade.entryPrice)) · Exit: \(formatPrice(trade.exitPrice))")
                .experienceStyle(.caption, color: colors.secondaryText)

            HStack(spacing: ExperienceSpacing.sm) {
                Text("\(contractsLabel(trade.contracts))")
                    .experienceStyle(.caption, color: colors.tertiaryText)
                Text("Points: \(formatSignedPoints(trade.points))")
                    .experienceStyle(.caption, color: colors.tertiaryText)
            }
        }
        .padding(.vertical, ExperienceSpacing.xxs)
    }

    private func pnlLine(_ pnl: Double?) -> String {
        guard let pnl else { return "P&L —" }
        return TradeDisplay.pnlText(Money(amount: Decimal(pnl)))
    }

    private func pnlColor(_ pnl: Double?) -> Color {
        guard let pnl else { return colors.secondaryText }
        if pnl > 0 { return colors.profit }
        if pnl < 0 { return colors.loss }
        return colors.secondaryText
    }

    private func formatPrice(_ value: Double) -> String {
        TradeDisplay.priceText(Decimal(value))
    }

    private func formatSignedPoints(_ value: Double) -> String {
        let prefix = value > 0 ? "+" : ""
        return "\(prefix)\(TradeDisplay.priceText(Decimal(value)))"
    }

    private func contractsLabel(_ value: Double) -> String {
        let n = Int(value.rounded())
        return "\(n) contract\(n == 1 ? "" : "s")"
    }
}
