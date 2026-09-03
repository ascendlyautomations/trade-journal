import Foundation

nonisolated enum ScreenshotPnLCalculator {
    struct Result: Hashable, Sendable {
        var calculatedGrossPnL: Decimal?
        var reportedPnL: Decimal?
        var warnings: [String]
    }

    static func evaluate(
        symbol: String,
        side: TradeSide,
        quantity: Decimal,
        entryPrice: Decimal?,
        exitPrice: Decimal?,
        reportedPnL: Decimal?,
        roundTrip: TradeFillAggregator.RoundTrip? = nil
    ) -> Result {
        var warnings: [String] = []
        let spec = FuturesInstrumentRegistry.resolve(symbol: symbol)

        let calculated: Decimal?
        if let roundTrip {
            calculated = calculateFromRoundTrip(roundTrip, spec: spec)
        } else if let spec, let entryPrice, let exitPrice {
            calculated = FuturesInstrumentRegistry.grossPnL(
                spec: spec,
                side: side,
                entryPrice: entryPrice,
                exitPrice: exitPrice,
                quantity: quantity
            )
        } else {
            calculated = nil
            if spec == nil, reportedPnL == nil {
                warnings.append("P&L missing")
            }
        }

        if let reportedPnL, let calculated {
            let delta = abs(reportedPnL - calculated)
            let tolerance = max(Decimal(1), abs(calculated) * Decimal(string: "0.05")!)
            if delta > tolerance {
                warnings.append("Review P&L")
            }
        } else if reportedPnL == nil, calculated == nil {
            warnings.append("P&L missing")
        }

        return Result(
            calculatedGrossPnL: calculated,
            reportedPnL: reportedPnL,
            warnings: warnings
        )
    }

    private static func calculateFromRoundTrip(
        _ trip: TradeFillAggregator.RoundTrip,
        spec: FuturesInstrumentRegistry.Spec?
    ) -> Decimal? {
        guard let spec else { return nil }
        let entryLegs = trip.entryFills.map { (price: $0.price, quantity: $0.quantity) }
        let exitLegs = trip.exitFills.map { (price: $0.price, quantity: $0.quantity) }
        guard let avgEntry = TradeFillWeightedPrice.average(entryLegs),
              let avgExit = TradeFillWeightedPrice.average(exitLegs)
        else { return nil }
        let matchedQty = min(
            entryLegs.reduce(0) { $0 + $1.quantity },
            exitLegs.reduce(0) { $0 + $1.quantity }
        )
        return FuturesInstrumentRegistry.grossPnL(
            spec: spec,
            side: trip.side,
            entryPrice: avgEntry,
            exitPrice: avgExit,
            quantity: matchedQty
        )
    }
}
