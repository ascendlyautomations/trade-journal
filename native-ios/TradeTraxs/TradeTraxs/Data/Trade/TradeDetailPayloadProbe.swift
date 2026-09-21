import Foundation

/// Phase 8C baseline — approximate detail JSON size without logging private fields.
nonisolated enum TradeDetailPayloadProbe {
    static func estimatedUtf8Bytes(for detail: TradeDetail) -> Int {
        var components: [String] = [
            detail.id.rawValue,
            detail.ownerProfileID.rawValue,
            detail.symbol.ticker,
            String(describing: detail.side),
        ]
        if let amount = detail.realizedPnL?.amount {
            components.append(String(describing: amount))
        }
        if let notes = detail.notes {
            components.append(String(notes.count))
        }
        if let psych = detail.psychologyNotes {
            components.append(String(psych.count))
        }
        return components.joined(separator: "|").utf8.count
    }
}
