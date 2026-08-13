import SwiftUI

struct CSVImportPreviewView: View {
    @Bindable var viewModel: CSVImportViewModel
    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    var body: some View {
        List {
            if let summary = viewModel.summary {
                Section {
                    Label("\(summary.format.displayName) CSV detected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(colors.accent)
                    Text("\(summary.successCount) trades detected · \(summary.failedCount) rows skipped")
                        .experienceStyle(.footnote, color: colors.secondaryText)
                }

                Section("Destination Account") {
                    if viewModel.eligibleAccounts.isEmpty {
                        Text("No accounts can accept new trades.")
                            .experienceStyle(.body, color: colors.secondaryText)
                    } else {
                        Picker("Account", selection: accountBinding) {
                            ForEach(viewModel.eligibleAccounts) { account in
                                Text(TradingAccountDisplay.title(for: account, audience: .owner))
                                    .tag(Optional(account.id))
                            }
                        }
                    }
                    Button("Manage Accounts") {
                        viewModel.openManageAccounts()
                    }
                    .accessibilityIdentifier("csvImport.manageAccounts")
                }

                Section("Summary") {
                    metricRow("Trades", "\(summary.readyCount + summary.needsReviewCount)")
                    metricRow("Net P&L", TradeDisplay.pnlText(Money(amount: summary.netPnL)))
                    metricRow("Wins", "\(summary.winCount)")
                    metricRow("Losses", "\(summary.lossCount)")
                    if summary.needsReviewCount > 0 {
                        metricRow("Need review", "\(summary.needsReviewCount)")
                    }
                    if summary.failedCount > 0 {
                        metricRow("Cannot import", "\(summary.failedCount)")
                    }
                }

                Section("Preview") {
                    ForEach(summary.trades.filter(\.isImportable).prefix(200)) { trade in
                        Button {
                            viewModel.beginReview(trade)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(trade.symbol)
                                        .experienceStyle(.headline, color: colors.primaryText)
                                    Text(trade.side == .long ? "LONG" : "SHORT")
                                        .experienceStyle(.caption, color: colors.secondaryText)
                                    Spacer()
                                    Text(TradeDisplay.pnlText(Money(amount: trade.realizedPnL)))
                                        .experienceStyle(
                                            .metric,
                                            color: theme.metricColor(
                                                for: NSDecimalNumber(decimal: trade.realizedPnL).doubleValue
                                            )
                                        )
                                }
                                Text(timeRange(trade))
                                    .experienceStyle(.caption, color: colors.tertiaryText)
                                if !trade.warningMessages.isEmpty {
                                    Text(trade.warningMessages.joined(separator: " · "))
                                        .experienceStyle(.caption, color: colors.secondaryText)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("csvImport.trade.\(trade.rowNumber)")
                    }
                }

                if !summary.failures.isEmpty {
                    Section("Skipped Rows") {
                        ForEach(summary.failures.prefix(20)) { failure in
                            Text("Row \(failure.rowNumber): \(failure.reason)")
                                .experienceStyle(.footnote, color: colors.secondaryText)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ExperienceButton(
                title: "Import \(viewModel.importableTrades.count) Trades",
                kind: .primary,
                isEnabled: viewModel.canImport,
                isLoading: viewModel.isImporting,
                accessibilityIdentifier: "csvImport.confirm"
            ) {
                viewModel.importTrades()
            }
            .padding(ExperienceSpacing.md)
            .background(colors.backgroundPrimary.opacity(0.96))
        }
        .sheet(item: reviewBinding) { trade in
            NavigationStack {
                CSVImportTradeReviewView(
                    trade: trade,
                    onSave: { viewModel.updateTrade($0) },
                    onCancel: { viewModel.cancelReview() }
                )
            }
        }
        .accessibilityIdentifier("csvImport.preview")
    }

    private var accountBinding: Binding<TradingAccountID?> {
        Binding(
            get: { viewModel.selectedAccountID ?? viewModel.eligibleAccounts.first?.id },
            set: { if let id = $0 { viewModel.selectAccount(id) } }
        )
    }

    private var reviewBinding: Binding<CSVParsedTrade?> {
        Binding(
            get: {
                guard let id = viewModel.reviewTradeID else { return nil }
                return viewModel.summary?.trades.first { $0.id == id }
            },
            set: { newValue in
                if newValue == nil { viewModel.cancelReview() }
            }
        )
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .experienceStyle(.body, color: colors.primaryText)
        }
    }

    private func timeRange(_ trade: CSVParsedTrade) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let start = formatter.string(from: trade.entryAt)
        if let exit = trade.exitAt {
            return "\(start) → \(formatter.string(from: exit))"
        }
        return start
    }
}
