import Foundation

/// Shared linked-trade field resolution for clip detail cards and feed clip overlays.
nonisolated enum ClipLinkedTradePresentation {
    struct Fields: Sendable, Equatable {
        let ticker: String
        let sideTitle: String
        let pnlText: String
        let entryPrice: String?
        let exitPrice: String?
        let entryTime: String
        let exitTime: String?
        let targetedRr: String?
        let realizedRr: String?
        let tradeDate: String
        let accountCaption: String?
    }

    static func fields(for trade: Trade) -> Fields {
        Fields(
            ticker: TradeDisplay.tickerText(trade.symbol),
            sideTitle: TradeDisplay.sideTitle(trade.side),
            pnlText: TradeDisplay.pnlText(trade.realizedPnL),
            entryPrice: optionalExecutionPrice(trade.entryPrice),
            exitPrice: optionalExecutionPrice(trade.exitPrice),
            entryTime: TradeDisplay.entryExecutionTimeText(entryAt: trade.entryAt, exitAt: trade.exitAt),
            exitTime: optionalExitExecutionTime(entryAt: trade.entryAt, exitAt: trade.exitAt),
            targetedRr: trade.riskReward.flatMap { TradeDisplay.compactRRText($0) },
            realizedRr: TradePointsAndRealizedRr.resolveRealizedRr(trade: trade)
                .flatMap { TradeDisplay.compactRRText($0) },
            tradeDate: TradeDisplay.dateText(trade.entryAt),
            accountCaption: trade.mode == .copyTraded
                ? nil
                : TradeDisplay.publicPostedAccountCaption(
                    providerName: nil,
                    accountMode: trade.accountMode,
                    publicAccountBadge: trade.publicAccountBadge
                )
        )
    }

    static func accessibilitySummary(for trade: Trade, description: String?) -> String {
        let fields = fields(for: trade)
        var parts = [
            "Linked trade",
            fields.ticker,
            fields.sideTitle,
            fields.pnlText,
        ]
        if let entryPrice = fields.entryPrice {
            parts.append("Entry \(entryPrice)")
        }
        if let exitPrice = fields.exitPrice {
            parts.append("Exit \(exitPrice)")
        }
        if let targetedRr = fields.targetedRr {
            parts.append("Targeted \(targetedRr)")
        }
        if let realizedRr = fields.realizedRr {
            parts.append("Realized \(realizedRr)")
        }
        parts.append(fields.tradeDate)
        if let account = fields.accountCaption {
            parts.append(account)
        }
        if let description {
            parts.append(description)
        }
        return parts.joined(separator: ", ")
    }

    private static func optionalExecutionPrice(_ value: Decimal?) -> String? {
        guard let value else { return nil }
        let formatted = TradeDisplay.executionPriceText(value, display: .fullPrecision)
        return formatted == "–" ? nil : formatted
    }

    private static func optionalExitExecutionTime(entryAt: Date, exitAt: Date?) -> String? {
        guard exitAt != nil else { return nil }
        let formatted = TradeDisplay.exitExecutionTimeText(entryAt: entryAt, exitAt: exitAt)
        return formatted == "–" ? nil : formatted
    }
}