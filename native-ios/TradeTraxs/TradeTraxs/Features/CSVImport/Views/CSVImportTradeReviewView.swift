import SwiftUI

/// Lightweight per-trade editor before bulk import.
struct CSVImportTradeReviewView: View {
    @State private var draft: CSVParsedTrade
    @State private var pnlText: String
    @State private var quantityText: String
    @State private var entryText: String
    @State private var exitText: String
    @State private var pointsText: String
    @State private var rrText: String
    @FocusState private var isPnlFocused: Bool

    let onSave: (CSVParsedTrade) -> Void
    let onCancel: () -> Void

    @Environment(\.themeColors) private var colors

    init(
        trade: CSVParsedTrade,
        onSave: @escaping (CSVParsedTrade) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: trade)
        _pnlText = State(initialValue: NumericInputFieldSupport.seedEditingText(from: trade.realizedPnL, style: .signedPnL))
        _quantityText = State(initialValue: NumericInputFieldSupport.seedEditingText(from: trade.quantity, style: .tradeQuantity))
        _entryText = State(initialValue: trade.entryPrice.map {
            NumericInputFieldSupport.seedEditingText(from: $0, style: .tradePrice)
        } ?? "")
        _exitText = State(initialValue: trade.exitPrice.map {
            NumericInputFieldSupport.seedEditingText(from: $0, style: .tradePrice)
        } ?? "")
        _pointsText = State(initialValue: trade.points.map {
            NumericInputFieldSupport.seedEditingText(from: $0, style: .tradeQuantity)
        } ?? "")
        _rrText = State(initialValue: trade.riskReward.map {
            NumericInputFieldSupport.seedEditingText(from: $0, style: .riskReward)
        } ?? "")
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        Form {
            Section("Trade") {
                TextField("Symbol", text: $draft.symbol)
                    .textInputAutocapitalization(.characters)
                Picker("Direction", selection: $draft.side) {
                    Text("Long").tag(TradeSide.long)
                    Text("Short").tag(TradeSide.short)
                }
                TextField("P&L", text: $pnlText.numericInput(.signedPnL))
                    .keyboardType(.decimalPad)
                    .focused($isPnlFocused)
                TextField("Contracts", text: $quantityText.numericInput(.tradeQuantity))
                    .keyboardType(.decimalPad)
                TextField("Entry Price", text: $entryText.numericInput(.tradePrice))
                    .keyboardType(.decimalPad)
                TextField("Exit Price", text: $exitText.numericInput(.tradePrice))
                    .keyboardType(.decimalPad)
                TextField("Points", text: $pointsText.numericInput(.tradeQuantity))
                    .keyboardType(.decimalPad)
                TextField("R:R", text: $rrText.numericInput(.riskReward))
                    .keyboardType(.decimalPad)
            }

            if !draft.warningMessages.isEmpty {
                Section("Warnings") {
                    ForEach(draft.warningMessages, id: \.self) { warning in
                        Text(warning)
                            .foregroundStyle(colors.secondaryText)
                    }
                }
            }
        }
        .experienceDashboardGroupedRows()
        .experienceNavigationTitle("Review Trade")
        .scrollDismissesKeyboard(.interactively)
        .experienceSignedDecimalKeyboardSignToggle(isActive: isPnlFocused) {
            pnlText = NumericInputFieldSupport.toggleSignOnDisplay(pnlText, style: .signedPnL)
        }
        .experienceFormKeyboard(isFocused: $isPnlFocused)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { saveTrade() }
                    .disabled(draft.symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .experienceProtectedFormDismiss()
        .accessibilityIdentifier("csvImport.review")
    }

    private func saveTrade() {
        guard let pnl = NumericInputFieldSupport.parse(pnlText, style: .signedPnL),
              let quantity = NumericInputFieldSupport.parse(quantityText, style: .tradeQuantity)
        else { return }

        var updated = draft
        updated.realizedPnL = pnl
        updated.quantity = quantity
        updated.entryPrice = NumericInputFieldSupport.parse(entryText, style: .tradePrice)
        updated.exitPrice = NumericInputFieldSupport.parse(exitText, style: .tradePrice)
        updated.points = NumericInputFieldSupport.parse(pointsText, style: .tradeQuantity)
        updated.riskReward = NumericInputFieldSupport.parse(rrText, style: .riskReward)
        onSave(updated)
    }
}
