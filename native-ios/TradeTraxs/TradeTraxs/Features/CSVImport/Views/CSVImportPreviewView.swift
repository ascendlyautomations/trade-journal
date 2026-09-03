import SwiftUI

struct CSVImportPreviewView: View {
    @Bindable var viewModel: CSVImportViewModel
    @Environment(\.themeColors) private var colors

    var body: some View {
        if let summary = viewModel.summary {
            TradeImportPreviewContent(
                config: TradeImportPreviewConfig(
                    sourceTitle: "\(summary.format.displayName) CSV detected",
                    sourceDetail: "\(summary.successCount) trades detected · \(summary.failedCount) rows skipped",
                    sourceSystemImage: "checkmark.circle.fill",
                    accessibilityPrefix: "csvImport"
                ),
                summary: summary,
                eligibleAccounts: viewModel.eligibleAccounts,
                selectedAccountID: Binding(
                    get: { viewModel.selectedAccountID },
                    set: { newValue in
                        if let id = newValue {
                            viewModel.selectAccount(id)
                        }
                    }
                ),
                ownerProfileID: viewModel.ownerProfileID,
                importableTrades: viewModel.importableTrades,
                canImport: viewModel.canImport,
                isImporting: viewModel.isImporting,
                reviewTradeID: viewModel.reviewTradeID,
                onManageAccounts: { viewModel.openManageAccounts() },
                onSelectAccount: { viewModel.selectAccount($0) },
                onBeginReview: { viewModel.beginReview($0) },
                onCancelReview: { viewModel.cancelReview() },
                onUpdateTrade: { viewModel.updateTrade($0) },
                onImport: { viewModel.importTrades() }
            )
        }
    }
}
