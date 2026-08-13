import Foundation

/// Maps domain Trade Detail state into the shared analyze-trade BFF payload.
///
/// Prompt construction stays on the server (`lib/analyzeTradePrompt.ts`).
nonisolated enum TradeAIMapper {
    static func makeContext(
        trade: Trade,
        notes: [TradeNote] = [],
        mediaAttachments: [TradeAIMediaAttachment] = []
    ) -> TradeAIContext {
        var attachments = mediaAttachments
        if attachments.isEmpty, let thumb = trade.thumbnail?.id, !thumb.isEmpty {
            attachments = [
                TradeAIMediaAttachment(kind: .screenshot, reference: thumb),
            ]
        }

        let noteBodies = notes.map(\.body).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let fallbackNote = trade.notePreview?.trimmingCharacters(in: .whitespacesAndNewlines)
        let journalNotes: [String] = {
            if !noteBodies.isEmpty { return noteBodies }
            if let fallbackNote, !fallbackNote.isEmpty { return [fallbackNote] }
            return []
        }()

        return TradeAIContext(
            tradeID: trade.id,
            tradePayload: makePayload(trade: trade, journalNotes: journalNotes),
            journalNotes: journalNotes,
            mediaAttachments: attachments
        )
    }

    static func makePayload(trade: Trade, journalNotes: [String]) -> TradeAITradePayload {
        let notesJoined = journalNotes.joined(separator: "\n")
        return TradeAITradePayload(
            id: trade.id.rawValue,
            ticker: trade.symbol.ticker,
            direction: sideLabel(trade.side),
            pnl: decimalString(trade.realizedPnL?.amount),
            rr: decimalString(trade.riskReward),
            entry_price: decimalString(trade.entryPrice),
            exit_price: decimalString(trade.exitPrice),
            entry_time: ISO8601.string(from: trade.entryAt),
            exit_time: trade.exitAt.map(ISO8601.string(from:)),
            session: trade.sessionLabel,
            strategy: trade.strategy,
            mode: modeLabel(trade.mode),
            contracts: decimalString(trade.quantity),
            notes: notesJoined.isEmpty ? nil : notesJoined,
            public_description: trade.publicCaption,
            user_id: trade.ownerProfileID.rawValue
        )
    }

    private static func sideLabel(_ side: TradeSide) -> String {
        switch side {
        case .long: return "Long"
        case .short: return "Short"
        }
    }

    private static func modeLabel(_ mode: TradeMode) -> String {
        mode.rawValue
    }

    private static func decimalString(_ value: Decimal?) -> String? {
        guard let value else { return nil }
        return NSDecimalNumber(decimal: value).stringValue
    }
}
