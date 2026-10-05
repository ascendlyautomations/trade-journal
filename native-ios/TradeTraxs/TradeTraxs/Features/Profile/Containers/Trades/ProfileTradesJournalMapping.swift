import Foundation

nonisolated enum ProfileTradesJournalMapping {
    /// Richer rows win on reconcile (V2 journal vs bootstrap TradeSummary-only).
    static func journalRichness(_ item: TradeOwnerJournalSummary) -> Int {
        var score = 0
        if item.accountID != nil { score += 1 }
        if item.copyTrade != nil { score += 2 }
        return score
    }

    static func journalItem(from summary: TradeSummary) -> TradeOwnerJournalSummary {
        TradeOwnerJournalSummary(
            summary: summary,
            accountID: nil,
            accountName: nil,
            strategy: nil,
            entryPrice: summary.entryPrice,
            exitPrice: summary.exitPrice,
            sessionLabel: nil,
            copyTrade: nil
        )
    }

    static func journalItems(from summaries: [TradeSummary]) -> [TradeOwnerJournalSummary] {
        summaries.map(journalItem(from:))
    }

    static func replaceSummaries(
        _ summaries: [TradeSummary],
        in journalItems: [TradeOwnerJournalSummary],
        preserveRicherExisting: Bool = false
    ) -> [TradeOwnerJournalSummary] {
        let byID = Dictionary(uniqueKeysWithValues: journalItems.map { ($0.id, $0) })
        return summaries.map { summary in
            if var existing = byID[summary.id] {
                let incoming = journalItem(from: summary)
                if preserveRicherExisting,
                   journalRichness(existing) > journalRichness(incoming)
                {
                    return existing
                }
                existing.summary = summary
                if existing.entryPrice == nil { existing.entryPrice = summary.entryPrice }
                if existing.exitPrice == nil { existing.exitPrice = summary.exitPrice }
                return existing
            }
            return journalItem(from: summary)
        }
    }
}
