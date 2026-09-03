import SwiftUI

/// Shared preview/review UI for CSV and screenshot bulk import flows.
struct TradeImportPreviewConfig: Equatable {
    var sourceTitle: String
    var sourceDetail: String
    var sourceSystemImage: String
    var accessibilityPrefix: String
}

struct TradeImportPreviewContent: View {
    let config: TradeImportPreviewConfig
    let summary: CSVParseSummary
    let eligibleAccounts: [TradingAccount]
    @Binding var selectedAccountID: TradingAccountID?
    let ownerProfileID: ProfileID?
    let importableTrades: [CSVParsedTrade]
    let canImport: Bool
    let isImporting: Bool
    let reviewTradeID: String?
    let onManageAccounts: () -> Void
    let onSelectAccount: (TradingAccountID) -> Void
    let onBeginReview: (CSVParsedTrade) -> Void
    let onCancelReview: () -> Void
    let onUpdateTrade: (CSVParsedTrade) -> Void
    let onImport: () -> Void
    /// Screenshot Phase 2 — fill breakdown + duplicate badges (nil for CSV import).
    var screenshotMetadataByTradeID: [String: ScreenshotImportTradeMetadata] = [:]
    var onToggleImportSelection: ((String) -> Void)? = nil

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    var body: some View {
        List {
            Section {
                Label(config.sourceTitle, systemImage: config.sourceSystemImage)
                    .foregroundStyle(colors.accent)
                Text(config.sourceDetail)
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }

            Section("Destination Account") {
                if eligibleAccounts.isEmpty {
                    Text("No accounts can accept new trades.")
                        .experienceStyle(.body, color: colors.secondaryText)
                } else {
                    Picker("Account", selection: accountBinding) {
                        ForEach(eligibleAccounts) { account in
                            OwnerAccountDropdownPickerLabel(account: account)
                                .tag(Optional(account.id))
                        }
                    }
                    .onAppear {
                        OwnerAccountDropdownSupport.logBoundary(
                            .csvImport,
                            accounts: eligibleAccounts,
                            profileID: ownerProfileID
                        )
                    }
                }
                Button("Manage Accounts", action: onManageAccounts)
                    .accessibilityIdentifier("\(config.accessibilityPrefix).manageAccounts")
            }

            Section("Summary") {
                metricRow("Trades", "\(summary.readyCount + summary.needsReviewCount)")
                metricRow("Net P&L", TradeDisplay.pnlText(Money(amount: summary.netPnL)))
                metricRow("Wins", "\(summary.winCount)")
                metricRow("Losses", "\(summary.lossCount)")
                if summary.needsReviewCount > 0 {
                    metricRow("Review required", "\(summary.needsReviewCount)")
                }
                if summary.failedCount > 0 {
                    metricRow("Cannot import", "\(summary.failedCount)")
                }
            }

            Section("Preview") {
                ForEach(summary.trades.filter(\.isImportable).prefix(200)) { trade in
                    VStack(alignment: .leading, spacing: 0) {
                        if let onToggle = onToggleImportSelection,
                           let metadata = screenshotMetadataByTradeID[trade.id]
                        {
                            Toggle(
                                isOn: Binding(
                                    get: { metadata.isSelectedForImport },
                                    set: { _ in onToggle(trade.id) }
                                )
                            ) {
                                EmptyView()
                            }
                            .labelsHidden()
                            .accessibilityIdentifier("\(config.accessibilityPrefix).toggle.\(trade.rowNumber)")
                        }

                        Button {
                            onBeginReview(trade)
                        } label: {
                            tradeRow(trade)
                        }
                        .buttonStyle(.plain)
                    }
                    .accessibilityIdentifier("\(config.accessibilityPrefix).trade.\(trade.rowNumber)")
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
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ExperienceButton(
                title: "Import \(importableTrades.count) Trades",
                kind: .primary,
                isEnabled: canImport,
                isLoading: isImporting,
                accessibilityIdentifier: "\(config.accessibilityPrefix).confirm"
            ) {
                onImport()
            }
            .padding(ExperienceSpacing.md)
            .background(colors.backgroundPrimary.opacity(0.96))
        }
        .sheet(item: reviewBinding) { trade in
            NavigationStack {
                CSVImportTradeReviewView(
                    trade: trade,
                    onSave: onUpdateTrade,
                    onCancel: onCancelReview
                )
            }
        }
        .accessibilityIdentifier("\(config.accessibilityPrefix).preview")
    }

    private var accountBinding: Binding<TradingAccountID?> {
        Binding(
            get: { selectedAccountID ?? eligibleAccounts.first?.id },
            set: { if let id = $0 { onSelectAccount(id) } }
        )
    }

    private var reviewBinding: Binding<CSVParsedTrade?> {
        Binding(
            get: {
                guard let id = reviewTradeID else { return nil }
                return summary.trades.first { $0.id == id }
            },
            set: { newValue in
                if newValue == nil { onCancelReview() }
            }
        )
    }

    @ViewBuilder
    private func tradeRow(_ trade: CSVParsedTrade) -> some View {
        let metadata = screenshotMetadataByTradeID[trade.id]
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(trade.symbol)
                    .experienceStyle(.headline, color: colors.primaryText)
                Text(trade.side == .long ? "LONG" : "SHORT")
                    .experienceStyle(.caption, color: colors.secondaryText)
                Spacer()
                statusBadge(for: trade, metadata: metadata)
            }

            if let entry = trade.entryPrice, let exit = trade.exitPrice {
                Text("Entry \(formatPrice(entry)) · Exit \(formatPrice(exit))")
                    .experienceStyle(.caption, color: colors.secondaryText)
            }

            HStack(spacing: ExperienceSpacing.sm) {
                Text("\(NSDecimalNumber(decimal: trade.quantity).stringValue) Contracts")
                    .experienceStyle(.caption, color: colors.tertiaryText)
                if trade.realizedPnL != 0 || trade.warningMessages.contains("P&L missing") {
                    Text("P&L \(TradeDisplay.pnlText(Money(amount: trade.realizedPnL)))")
                        .experienceStyle(.caption, color: colors.tertiaryText)
                }
                if let points = trade.points {
                    Text("Pts \(formatPrice(points))")
                        .experienceStyle(.caption, color: colors.tertiaryText)
                }
            }

            if let metadata, metadata.aggregationSource == .fillAggregation,
               metadata.entryFillCount + metadata.exitFillCount > 0
            {
                Text("\(metadata.entryFillCount) entry fills · \(metadata.exitFillCount) exit fills")
                    .experienceStyle(.caption, color: colors.tertiaryText)
            }

            Text(timeRange(trade))
                .experienceStyle(.caption, color: colors.tertiaryText)

            if let metadata, !metadata.fills.isEmpty {
                DisclosureGroup("Executions (\(metadata.fills.count))") {
                    ForEach(metadata.fills) { fill in
                        Text("\(fill.sideLabel) \(NSDecimalNumber(decimal: fill.quantity).stringValue) @ \(formatPrice(fill.price))")
                            .experienceStyle(.caption, color: colors.secondaryText)
                    }
                }
                .font(.caption)
                .foregroundStyle(colors.secondaryText)
            }

            if !trade.warningMessages.isEmpty {
                Text(trade.warningMessages.joined(separator: " · "))
                    .experienceStyle(.caption, color: colors.secondaryText)
            }
        }
    }

    @ViewBuilder
    private func statusBadge(
        for trade: CSVParsedTrade,
        metadata: ScreenshotImportTradeMetadata?
    ) -> some View {
        if let metadata, metadata.duplicateClassification == .exactDuplicate {
            Label("Exact duplicate", systemImage: "doc.on.doc.fill")
                .font(.caption)
                .foregroundStyle(colors.secondaryText)
        } else if let metadata, metadata.duplicateClassification == .possibleDuplicate {
            Label("Possible duplicate", systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(colors.secondaryText)
        } else if metadata?.extractionSource == .aiAssisted {
            Label("AI-assisted", systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(colors.secondaryText)
        } else if metadata?.pnlSource == .calculated {
            Label("Calculated", systemImage: "function")
                .font(.caption)
                .foregroundStyle(colors.accent)
        } else if trade.status == .ready {
            Label("Ready", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(colors.accent)
        } else {
            Label("Review required", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(colors.secondaryText)
        }
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .experienceStyle(.body, color: colors.primaryText)
        }
    }

    private func formatPrice(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private func timeRange(_ trade: CSVParsedTrade) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(identifier: "America/New_York")
        dateFormatter.dateFormat = "MMM d"

        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none
        timeFormatter.timeZone = TimeZone(identifier: "America/New_York")

        let dateLabel = dateFormatter.string(from: trade.entryAt)
        let start = timeFormatter.string(from: trade.entryAt)
        if let exit = trade.exitAt {
            return "\(dateLabel) · \(start) → \(timeFormatter.string(from: exit))"
        }
        return "\(dateLabel) · \(start)"
    }
}
