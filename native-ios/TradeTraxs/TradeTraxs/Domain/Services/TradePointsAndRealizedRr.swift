import Foundation

nonisolated enum TradePointsAndRealizedRr {
    /// Beyond this, treat stored/computed R as bad data for analytics.
    static let realizedRrAnalyticsAbsMax = Decimal(25)

    static func positivePointsTarget(_ value: Decimal?) -> Decimal? {
        guard let value, value > 0 else { return nil }
        return value
    }

    static func positiveTargetedRr(_ value: Decimal?) -> Decimal? {
        guard let value, value > 0 else { return nil }
        return value
    }

    static func nonnegativeMaxRr(_ value: Decimal?) -> Decimal? {
        guard let value, value >= 0 else { return nil }
        return value
    }

    static func actualPointsFromPrices(trade: Trade) -> Decimal? {
        guard let entry = trade.entryPrice, let exit = trade.exitPrice else { return nil }
        return FuturesInstrumentRegistry.directionalPoints(
            side: trade.side,
            entry: entry,
            exit: exit
        )
    }

    static func computeRealizedRrFromDraft(_ draft: TradeDraft) -> Decimal? {
        guard let pointsTargeted = positivePointsTarget(draft.points),
              let targetedRr = positiveTargetedRr(draft.riskReward),
              let entry = draft.entryPrice,
              let exit = draft.exitPrice
        else { return nil }
        let actual = FuturesInstrumentRegistry.directionalPoints(
            side: draft.side,
            entry: entry,
            exit: exit
        )
        return (actual * targetedRr) / pointsTargeted
    }

    static func computeRealizedRrFromPricesAndPlan(trade: Trade) -> Decimal? {
        guard let pointsTargeted = positivePointsTarget(trade.points),
              let targetedRr = positiveTargetedRr(trade.riskReward),
              let actual = actualPointsFromPrices(trade: trade)
        else { return nil }
        if storedPointsMatchPriceActualMove(trade: trade) { return nil }
        if planPointsInconsistentWithPriceMove(trade: trade) { return nil }
        let realized = (actual * targetedRr) / pointsTargeted
        return isPlausibleRealizedRr(realized) ? realized : nil
    }

    static func resolveRealizedRr(trade: Trade) -> Decimal? {
        if let stored = trade.realizedRr, isPlausibleRealizedRr(stored) {
            return stored
        }
        if storedPointsMatchPriceActualMove(trade: trade),
           let legacy = legacyStoredRrAsRealized(trade: trade)
        {
            return legacy
        }
        if let computed = computeRealizedRrFromPricesAndPlan(trade: trade) {
            return computed
        }
        if isAutomaticOrLegacyImport(trade) {
            return legacyStoredRrAsRealized(trade: trade)
        }
        return nil
    }

    static func isPlausibleRealizedRr(_ value: Decimal) -> Bool {
        abs(value) <= realizedRrAnalyticsAbsMax
    }

    static func storedPointsMatchPriceActualMove(trade: Trade) -> Bool {
        guard let points = positivePointsTarget(trade.points),
              let actual = actualPointsFromPrices(trade: trade)
        else { return false }
        let scale = max(abs(points), abs(actual), Decimal(string: "0.000001")!)
        return abs(actual - points) / scale <= Decimal(string: "0.25")!
    }

    static func planPointsInconsistentWithPriceMove(trade: Trade) -> Bool {
        guard let points = positivePointsTarget(trade.points),
              let actual = actualPointsFromPrices(trade: trade)
        else { return false }
        if abs(actual) < Decimal(string: "0.000001")! { return false }
        return abs(actual) / points > 10
    }

    private static func legacyStoredRrAsRealized(trade: Trade) -> Decimal? {
        guard let legacy = trade.riskReward, isPlausibleRealizedRr(legacy) else { return nil }
        return legacy
    }

    static func computeActualPoints(trade: Trade) -> Decimal? {
        guard let pointsTargeted = positivePointsTarget(trade.points),
              let targetedRr = positiveTargetedRr(trade.riskReward),
              let realized = resolveRealizedRr(trade: trade)
        else { return nil }
        return (pointsTargeted / targetedRr) * realized
    }

    static func averageRealizedRr(trades: [Trade]) -> Decimal? {
        var sum = Decimal(0)
        var count = 0
        for trade in trades {
            guard let rr = resolveRealizedRr(trade: trade) else { continue }
            sum += rr
            count += 1
        }
        guard count > 0 else { return nil }
        return sum / Decimal(count)
    }

    static func validateManualRiskFields(
        pnl: Decimal?,
        pointsText: String,
        rrText: String,
        maxRrText: String,
        parsePoints: (String) -> Decimal?,
        parseRr: (String) -> Decimal?
    ) -> (points: String?, rr: String?, maxRr: String?) {
        let pnlValue = pnl ?? 0
        let requireMax = pnlValue <= 0
        var pointsError: String?
        var rrError: String?
        var maxError: String?

        if positivePointsTarget(parsePoints(pointsText)) == nil {
            pointsError = "Points Targeted is required (positive number)."
        }
        if positiveTargetedRr(parseRr(rrText)) == nil {
            rrError = "Targeted Risk/Reward is required (positive number)."
        }
        if requireMax {
            if nonnegativeMaxRr(parseRr(maxRrText)) == nil {
                maxError = "Max R:R Reached is required for breakeven and losing trades (0 or greater)."
            }
        } else if !maxRrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  parseRr(maxRrText) == nil
        {
            maxError = "Enter a valid Max R:R Reached (0 or greater)."
        }

        return (pointsError, rrError, maxError)
    }

    private static func isAutomaticOrLegacyImport(_ trade: Trade) -> Bool {
        guard let source = trade.importSource else { return false }
        return source != .manual
    }
}
