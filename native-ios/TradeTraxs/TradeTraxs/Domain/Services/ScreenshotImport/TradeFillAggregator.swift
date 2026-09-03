import Foundation

/// Weighted price helpers for fill aggregation.
nonisolated enum TradeFillWeightedPrice {
    static func average(_ legs: [(price: Decimal, quantity: Decimal)]) -> Decimal? {
        guard !legs.isEmpty else { return nil }
        var totalQty: Decimal = 0
        var totalNotional: Decimal = 0
        for leg in legs {
            guard leg.quantity > 0 else { continue }
            totalQty += leg.quantity
            totalNotional += leg.price * leg.quantity
        }
        guard totalQty > 0 else { return nil }
        return totalNotional / totalQty
    }
}

/// Deterministic FIFO fill aggregation — emits completed round trips when flat.
nonisolated enum TradeFillAggregator {
    struct RoundTrip: Hashable, Sendable {
        var symbol: String
        var side: TradeSide
        var quantity: Decimal
        var entryPrice: Decimal
        var exitPrice: Decimal
        var entryAt: Date
        var exitAt: Date
        var entryFills: [ParsedTradeFill]
        var exitFills: [ParsedTradeFill]
        var reportedPnL: Decimal?
        var aggregatedFees: Decimal
        var warnings: [String]
    }

    static func aggregate(fills input: [ParsedTradeFill]) -> [RoundTrip] {
        let sorted = input.sorted {
            if $0.executedAt != $1.executedAt { return $0.executedAt < $1.executedAt }
            if $0.sourceImageIndex != $1.sourceImageIndex { return $0.sourceImageIndex < $1.sourceImageIndex }
            return $0.sourceRowIndex < $1.sourceRowIndex
        }

        var completed: [RoundTrip] = []
        let symbols = Set(sorted.map(\.symbol))

        for symbol in symbols.sorted() {
            let symbolFills = sorted.filter { $0.symbol == symbol }
            completed.append(contentsOf: aggregateSymbol(symbolFills))
        }
        return completed
    }

    private static func aggregateSymbol(_ fills: [ParsedTradeFill]) -> [RoundTrip] {
        var position: Decimal = 0
        var entryFills: [ParsedTradeFill] = []
        var exitFills: [ParsedTradeFill] = []
        var completed: [RoundTrip] = []
        var warnings: [String] = []

        for fill in fills {
            let delta = fill.signedQuantityDelta
            let previous = position
            let next = position + delta

            if previous == 0 {
                entryFills = [fill]
                exitFills = []
                position = next
                continue
            }

            if previous * delta > 0 {
                entryFills.append(fill)
                position = next
                continue
            }

            if abs(delta) > abs(previous), previous != 0 {
                let (closeFill, openFill) = splitFill(fill, closeQuantity: abs(previous))
                exitFills.append(closeFill)
                position = 0
                if let trip = buildRoundTrip(
                    symbol: fill.symbol,
                    entryFills: entryFills,
                    exitFills: exitFills,
                    warnings: warnings
                ) {
                    completed.append(trip)
                } else {
                    warnings.append("Review grouping")
                }
                entryFills = openFill.map { [$0] } ?? []
                exitFills = []
                position = openFill?.signedQuantityDelta ?? 0
                continue
            }

            exitFills.append(fill)
            position = next

            if position == 0 {
                if let trip = buildRoundTrip(
                    symbol: fill.symbol,
                    entryFills: entryFills,
                    exitFills: exitFills,
                    warnings: warnings
                ) {
                    completed.append(trip)
                } else {
                    warnings.append("Review grouping")
                }
                entryFills = []
                exitFills = []
                warnings = []
            } else if previous * next < 0 {
                warnings.append("Review grouping")
            }
        }

        if position != 0, !entryFills.isEmpty {
            completed.append(
                RoundTrip(
                    symbol: entryFills[0].symbol,
                    side: position > 0 ? .long : .short,
                    quantity: abs(position),
                    entryPrice: TradeFillWeightedPrice.average(entryFills.map { ($0.price, $0.quantity) }) ?? 0,
                    exitPrice: TradeFillWeightedPrice.average(exitFills.map { ($0.price, $0.quantity) }) ?? 0,
                    entryAt: entryFills.first?.executedAt ?? Date(),
                    exitAt: exitFills.last?.executedAt ?? entryFills.last?.executedAt ?? Date(),
                    entryFills: entryFills,
                    exitFills: exitFills,
                    reportedPnL: nil,
                    aggregatedFees: aggregateFees(entryFills + exitFills),
                    warnings: ["Review grouping"] + warnings
                )
            )
        }

        return completed
    }

    private static func splitFill(
        _ fill: ParsedTradeFill,
        closeQuantity: Decimal
    ) -> (close: ParsedTradeFill, open: ParsedTradeFill?) {
        let remainder = fill.quantity - closeQuantity
        let close = ParsedTradeFill(
            id: "\(fill.id)-close",
            symbol: fill.symbol,
            action: fill.action,
            quantity: closeQuantity,
            price: fill.price,
            executedAt: fill.executedAt,
            reportedPnL: fill.reportedPnL,
            commission: proportionalCommission(fill.commission, part: closeQuantity, totalQty: fill.quantity),
            executionID: fill.executionID,
            orderID: fill.orderID,
            sourcePlatform: fill.sourcePlatform,
            sourceImageIndex: fill.sourceImageIndex,
            sourceRowIndex: fill.sourceRowIndex,
            warnings: fill.warnings
        )
        guard remainder > 0 else { return (close, nil) }
        let open = ParsedTradeFill(
            id: "\(fill.id)-open",
            symbol: fill.symbol,
            action: fill.action,
            quantity: remainder,
            price: fill.price,
            executedAt: fill.executedAt,
            reportedPnL: nil,
            commission: proportionalCommission(fill.commission, part: remainder, totalQty: fill.quantity),
            executionID: nil,
            orderID: nil,
            sourcePlatform: fill.sourcePlatform,
            sourceImageIndex: fill.sourceImageIndex,
            sourceRowIndex: fill.sourceRowIndex,
            warnings: fill.warnings + ["Split fill remainder"]
        )
        return (close, open)
    }

    private static func proportionalCommission(
        _ total: Decimal?,
        part: Decimal,
        totalQty: Decimal
    ) -> Decimal? {
        guard let total, totalQty > 0 else { return nil }
        return (total * part) / totalQty
    }

    private static func buildRoundTrip(
        symbol: String,
        entryFills: [ParsedTradeFill],
        exitFills: [ParsedTradeFill],
        warnings: [String]
    ) -> RoundTrip? {
        guard !entryFills.isEmpty, !exitFills.isEmpty else { return nil }
        let side: TradeSide = entryFills.first?.action == .buy ? .long : .short
        guard let entryPrice = TradeFillWeightedPrice.average(entryFills.map { ($0.price, $0.quantity) }),
              let exitPrice = TradeFillWeightedPrice.average(exitFills.map { ($0.price, $0.quantity) })
        else { return nil }

        let quantity = min(
            entryFills.reduce(0) { $0 + $1.quantity },
            exitFills.reduce(0) { $0 + $1.quantity }
        )
        guard quantity > 0 else { return nil }

        let reported = (entryFills + exitFills).compactMap(\.reportedPnL).reduce(0, +)
        let reportedPnL: Decimal? = reported == 0 ? nil : reported

        return RoundTrip(
            symbol: symbol,
            side: side,
            quantity: quantity,
            entryPrice: entryPrice,
            exitPrice: exitPrice,
            entryAt: entryFills.first!.executedAt,
            exitAt: exitFills.last!.executedAt,
            entryFills: entryFills,
            exitFills: exitFills,
            reportedPnL: reportedPnL,
            aggregatedFees: aggregateFees(entryFills + exitFills),
            warnings: warnings
        )
    }

    private static func aggregateFees(_ fills: [ParsedTradeFill]) -> Decimal {
        fills.compactMap(\.commission).reduce(0, +)
    }
}
