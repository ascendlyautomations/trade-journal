import Foundation

nonisolated enum TradePointsAndRealizedRr {
    /// Beyond this, treat stored/computed R as bad data for analytics.
    static let realizedRrAnalyticsAbsMax = Decimal(25)

    static let realizedRrCannotExceedTargetedMessage =
        "Realized R:R cannot exceed Targeted R:R."

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

    /// Manual Add/Edit save, never stores zero when data is insufficient (nil instead).
    static func computeRealizedRrFromDraft(_ draft: TradeDraft) -> Decimal? {
        realizedRrForManualSave(draft: draft)
    }

    static func canComputeExitRrFromPrices(draft: TradeDraft) -> Bool {
        computeExitRrFromPricesAndPlan(draft: draft) != nil
    }

    static func computeExitRrFromPricesAndPlan(draft: TradeDraft) -> Decimal? {
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
        let realized = (actual * targetedRr) / pointsTargeted
        guard !storedPointsMatchPriceActualMove(
            points: draft.points,
            side: draft.side,
            entry: entry,
            exit: exit
        ),
        !planPointsInconsistentWithPriceMove(
            points: draft.points,
            side: draft.side,
            entry: entry,
            exit: exit
        )
        else { return nil }
        return isPlausibleRealizedRr(realized) ? realized : nil
    }

    static func realizedRrForManualSave(draft: TradeDraft) -> Decimal? {
        let pnl = draft.realizedPnL?.amount ?? 0
        if draft.fullTakeProfit, pnl > 0, let targeted = positiveTargetedRr(draft.riskReward) {
            return targeted
        }
        if draft.earlyExit, pnl > 0 {
            if let computed = computeExitRrFromPricesAndPlan(draft: draft) {
                return computed
            }
            if let manual = draft.exitRr, isPlausibleRealizedRr(manual) {
                return manual
            }
            return nil
        }
        return computeExitRrFromPricesAndPlan(draft: draft)
    }

    /// Winning manual saves, realized R:R (computed or Exit R:R) must not exceed targeted R:R.
    static func validateRealizedRrAgainstTargeted(draft: TradeDraft) -> String? {
        let pnl = draft.realizedPnL?.amount ?? 0
        guard pnl > 0 else { return nil }
        guard let targeted = positiveTargetedRr(draft.riskReward) else { return nil }
        if draft.fullTakeProfit { return nil }
        guard let realized = realizedRrForManualSave(draft: draft) else { return nil }
        guard realized > targeted else { return nil }
        return realizedRrCannotExceedTargetedMessage
    }

    /// Dashboard Avg Targeted R:R, mean stored targeted `rr`; excludes trades without a positive target.
    static func averageTargetedRr(trades: [Trade]) -> Decimal? {
        var sum = Decimal(0)
        var count = 0
        for trade in trades {
            guard let rr = positiveTargetedRr(trade.riskReward) else { continue }
            sum += rr
            count += 1
        }
        guard count > 0 else { return nil }
        return sum / Decimal(count)
    }

    /// Mean stored max R:R reached; excludes trades without `maxRrReached` (not targeted or realized R:R).
    static func averageMaxRrReached(trades: [Trade]) -> Decimal? {
        var sum = Decimal(0)
        var count = 0
        for trade in trades {
            guard let maxRr = trade.maxRrReached else { continue }
            sum += maxRr
            count += 1
        }
        guard count > 0 else { return nil }
        return sum / Decimal(count)
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
        fullTakeProfit: Bool,
        earlyExit: Bool,
        exitRrText: String,
        parsePoints: (String) -> Decimal?,
        parseRr: (String) -> Decimal?,
        canComputeExitRr: Bool,
        previewDraft: TradeDraft
    ) -> (
        points: String?,
        rr: String?,
        maxRr: String?,
        exitRr: String?,
        outcomeMode: String?,
        realizedRr: String?
    ) {
        let pnlValue = pnl ?? 0
        let requireMax = pnlValue <= 0 || earlyExit
        var pointsError: String?
        var rrError: String?
        var maxError: String?
        var exitError: String?
        var modeError: String?
        var realizedError: String?

        if fullTakeProfit && earlyExit {
            modeError = "Choose Full TP or Early Exit, not both."
        }

        if positivePointsTarget(parsePoints(pointsText)) == nil {
            pointsError = "Points Targeted is required (positive number)."
        }
        if positiveTargetedRr(parseRr(rrText)) == nil {
            rrError = "Targeted Risk/Reward is required (positive number)."
        }
        if requireMax, nonnegativeMaxRr(parseRr(maxRrText)) == nil {
            maxError = earlyExit
                ? "Max R:R Reached is required for early exits (0 or greater)."
                : "Max R:R Reached is required for breakeven and losing trades (0 or greater)."
        } else if !requireMax,
                  !maxRrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  nonnegativeMaxRr(parseRr(maxRrText)) == nil
        {
            maxError = "Enter a valid Max R:R Reached (0 or greater)."
        }

        if earlyExit, pnlValue > 0, !canComputeExitRr {
            let trimmed = exitRrText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                exitError = "Exit R:R is required when entry and exit prices cannot derive it."
            } else if let parsed = parseRr(exitRrText), !isPlausibleRealizedRr(parsed) {
                exitError = "Enter a valid Exit R:R."
            } else if let targeted = positiveTargetedRr(parseRr(rrText)),
                      let parsed = parseRr(exitRrText),
                      parsed > targeted
            {
                exitError = realizedRrCannotExceedTargetedMessage
            }
        }

        if exitError == nil, let cap = validateRealizedRrAgainstTargeted(draft: previewDraft) {
            if earlyExit, pnlValue > 0, !canComputeExitRr {
                exitError = cap
            } else {
                realizedError = cap
            }
        }

        return (pointsError, rrError, maxError, exitError, modeError, realizedError)
    }

    private static func storedPointsMatchPriceActualMove(
        points: Decimal?,
        side: TradeSide,
        entry: Decimal,
        exit: Decimal
    ) -> Bool {
        let trade = Trade(
            id: TradeID("validation"),
            ownerProfileID: ProfileID("validation"),
            symbol: Symbol(ticker: "X"),
            side: side,
            mode: .live,
            quantity: 1,
            entryPrice: entry,
            exitPrice: exit,
            entryAt: Date(),
            points: points,
            visibility: .private,
            createdAt: Date(),
            updatedAt: Date()
        )
        return storedPointsMatchPriceActualMove(trade: trade)
    }

    private static func planPointsInconsistentWithPriceMove(
        points: Decimal?,
        side: TradeSide,
        entry: Decimal,
        exit: Decimal
    ) -> Bool {
        let trade = Trade(
            id: TradeID("validation"),
            ownerProfileID: ProfileID("validation"),
            symbol: Symbol(ticker: "X"),
            side: side,
            mode: .live,
            quantity: 1,
            entryPrice: entry,
            exitPrice: exit,
            entryAt: Date(),
            points: points,
            visibility: .private,
            createdAt: Date(),
            updatedAt: Date()
        )
        return planPointsInconsistentWithPriceMove(trade: trade)
    }

    private static func isAutomaticOrLegacyImport(_ trade: Trade) -> Bool {
        guard let source = trade.importSource else { return false }
        return source != .manual
    }
}
