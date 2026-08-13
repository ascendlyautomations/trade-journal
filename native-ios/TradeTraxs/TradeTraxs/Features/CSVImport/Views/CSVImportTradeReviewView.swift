import SwiftUI

/// Lightweight per-trade editor before bulk import.
struct CSVImportTradeReviewView: View {
    @State private var draft: CSVParsedTrade
    let onSave: (CSVParsedTrade) -> Void
    let onCancel: () -> Void

    @Environment(\.themeColors) private var colors

    init(
        trade: CSVParsedTrade,
        onSave: @escaping (CSVParsedTrade) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: trade)
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
                TextField("P&L", text: pnlBinding)
                    .keyboardType(.decimalPad)
                TextField("Contracts", text: quantityBinding)
                    .keyboardType(.decimalPad)
                TextField("Entry Price", text: entryBinding)
                    .keyboardType(.decimalPad)
                TextField("Exit Price", text: exitBinding)
                    .keyboardType(.decimalPad)
                TextField("Points", text: pointsBinding)
                    .keyboardType(.decimalPad)
                TextField("R:R", text: rrBinding)
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
        .experienceNavigationTitle("Review Trade")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { onSave(draft) }
                    .disabled(draft.symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .accessibilityIdentifier("csvImport.review")
    }

    private var pnlBinding: Binding<String> {
        decimalBinding(\.realizedPnL, required: true)
    }

    private var quantityBinding: Binding<String> {
        decimalBinding(\.quantity, required: true)
    }

    private var entryBinding: Binding<String> {
        optionalDecimalBinding(\.entryPrice)
    }

    private var exitBinding: Binding<String> {
        optionalDecimalBinding(\.exitPrice)
    }

    private var pointsBinding: Binding<String> {
        optionalDecimalBinding(\.points)
    }

    private var rrBinding: Binding<String> {
        optionalDecimalBinding(\.riskReward)
    }

    private func decimalBinding(
        _ keyPath: WritableKeyPath<CSVParsedTrade, Decimal>,
        required: Bool
    ) -> Binding<String> {
        Binding(
            get: { NSDecimalNumber(decimal: draft[keyPath: keyPath]).stringValue },
            set: { raw in
                if let value = CSVNumericParser.parse(raw) {
                    draft[keyPath: keyPath] = value
                } else if !required, raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // no-op for required
                }
            }
        )
    }

    private func optionalDecimalBinding(
        _ keyPath: WritableKeyPath<CSVParsedTrade, Decimal?>
    ) -> Binding<String> {
        Binding(
            get: {
                guard let value = draft[keyPath: keyPath] else { return "" }
                return NSDecimalNumber(decimal: value).stringValue
            },
            set: { raw in
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                draft[keyPath: keyPath] = trimmed.isEmpty ? nil : CSVNumericParser.parse(trimmed)
            }
        )
    }
}
