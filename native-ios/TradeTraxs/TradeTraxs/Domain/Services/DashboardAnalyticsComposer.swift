import Foundation

/// Compose Dashboard presentation metrics from additive daily-stat ingredients (V3 contract).
nonisolated enum DashboardAnalyticsComposer {
    struct Ingredients: Sendable, Equatable {
        var tradeCount: Int
        var winCount: Int
        var lossCount: Int
        var breakevenCount: Int
        var netPnL: Decimal
        var grossProfit: Decimal
        var grossLoss: Decimal
        var longCount: Int
        var longPnL: Decimal
        var shortCount: Int
        var shortPnL: Decimal
        var sumRR: Decimal
        var rrCount: Int
        var sumHoldSeconds: Decimal
        var holdCount: Int
        var largestWin: Decimal?
        var largestLoss: Decimal?
    }

    static func ingredients(from wire: AnalyticsDashboardMetricsWireV1) -> Ingredients {
        Ingredients(
            tradeCount: wire.trade_count,
            winCount: wire.win_count,
            lossCount: wire.loss_count,
            breakevenCount: wire.breakeven_count,
            netPnL: decimal(wire.net_pnl),
            grossProfit: decimal(wire.gross_profit),
            grossLoss: decimal(wire.gross_loss),
            longCount: wire.long_count,
            longPnL: decimal(wire.long_pnl),
            shortCount: wire.short_count,
            shortPnL: decimal(wire.short_pnl),
            sumRR: decimal(wire.sum_rr),
            rrCount: wire.rr_count,
            sumHoldSeconds: decimal(wire.sum_hold_seconds),
            holdCount: wire.hold_count,
            largestWin: wire.largest_win.flatMap { decimal($0) },
            largestLoss: wire.largest_loss.flatMap { decimal($0) }
        )
    }

    static func winRate(_ s: Ingredients) -> Decimal? {
        guard s.tradeCount > 0 else { return nil }
        return Decimal(s.winCount) / Decimal(s.tradeCount)
    }

    static func profitFactor(_ s: Ingredients) -> Decimal? {
        guard s.grossLoss < 0 else { return s.grossProfit > 0 ? nil : nil }
        let denom = abs(s.grossLoss)
        guard denom > 0 else { return nil }
        return s.grossProfit / denom
    }

    static func averageWinner(_ s: Ingredients) -> Decimal? {
        guard s.winCount > 0 else { return nil }
        return s.grossProfit / Decimal(s.winCount)
    }

    static func averageLoserMagnitude(_ s: Ingredients) -> Decimal? {
        guard s.lossCount > 0 else { return nil }
        return abs(s.grossLoss) / Decimal(s.lossCount)
    }

    static func averageRR(_ s: Ingredients) -> Decimal? {
        guard s.rrCount > 0 else { return nil }
        return s.sumRR / Decimal(s.rrCount)
    }

    static func averageHoldSeconds(_ s: Ingredients) -> Decimal? {
        guard s.holdCount > 0 else { return nil }
        return s.sumHoldSeconds / Decimal(s.holdCount)
    }

    static func expectancy(_ s: Ingredients) -> Decimal? {
        guard s.tradeCount > 0 else { return nil }
        let wr = winRate(s) ?? 0
        let lr = Decimal(s.lossCount) / Decimal(s.tradeCount)
        return wr * (averageWinner(s) ?? 0) - lr * (averageLoserMagnitude(s) ?? 0)
    }

    private static func decimal(_ wire: PostgresFlexibleDouble) -> Decimal {
        guard let value = wire.value else { return 0 }
        return Decimal(value)
    }
}
