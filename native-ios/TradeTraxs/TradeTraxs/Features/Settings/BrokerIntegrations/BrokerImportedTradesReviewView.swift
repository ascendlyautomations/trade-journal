import SwiftUI

/// Phase 1 enrichment — sequential native trade edit for broker-imported IDs.
struct BrokerImportedTradesReviewView: View {
    let tradeIDs: [TradeID]
    let data: DataEnvironment
    let onFinished: () -> Void

    @State private var index = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    var body: some View {
        NavigationStack {
            Group {
                if index < tradeIDs.count {
                    AddTradeView(
                        data: data,
                        mode: .edit(tradeIDs[index]),
                        embeddedInTradeEntryHub: false,
                        onDismiss: { advance() }
                    )
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Skip") { advance() }
                        }
                        ToolbarItem(placement: .principal) {
                            Text("Review \(index + 1) of \(tradeIDs.count)")
                                .experienceStyle(.footnote, color: colors.secondaryText)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "All set",
                        systemImage: "checkmark.circle",
                        description: Text("Journal updates were saved.")
                    )
                }
            }
            .experienceNavigationTitle("Review Imported Trades")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { finish() }
                }
            }
        }
    }

    private func advance() {
        if index + 1 >= tradeIDs.count {
            finish()
        } else {
            index += 1
        }
    }

    private func finish() {
        onFinished()
        dismiss()
    }
}
