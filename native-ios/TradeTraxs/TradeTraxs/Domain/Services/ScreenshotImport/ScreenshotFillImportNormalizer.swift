import Foundation

/// Converts aggregated round trips into import candidates + review metadata.
nonisolated enum ScreenshotFillImportNormalizer {
    static func normalize(
        roundTrips: [TradeFillAggregator.RoundTrip],
        startingRowNumber: Int = 1,
        accountID: String? = nil
    ) -> [(trade: CSVParsedTrade, metadata: ScreenshotImportTradeMetadata)] {
        roundTrips.enumerated().compactMap { index, trip in
            normalizeRoundTrip(trip, rowNumber: startingRowNumber + index, accountID: accountID)
        }
    }

    static func normalizeRoundTrip(
        _ trip: TradeFillAggregator.RoundTrip,
        rowNumber: Int,
        accountID: String? = nil
    ) -> (trade: CSVParsedTrade, metadata: ScreenshotImportTradeMetadata)? {
        guard trip.quantity > 0 else { return nil }

        let points = FuturesInstrumentRegistry.directionalPoints(
            side: trip.side,
            entry: trip.entryPrice,
            exit: trip.exitPrice
        )
        let pnlEval = ScreenshotPnLCalculator.evaluate(
            symbol: trip.symbol,
            side: trip.side,
            quantity: trip.quantity,
            entryPrice: trip.entryPrice,
            exitPrice: trip.exitPrice,
            reportedPnL: trip.reportedPnL,
            roundTrip: trip
        )

        var warnings = Array(Set(trip.warnings + pnlEval.warnings))
        var notes = ""
        if trip.aggregatedFees > 0 {
            let feeText = NSDecimalNumber(decimal: trip.aggregatedFees).stringValue
            notes = "Fees: $\(feeText)"
        }

        let realizedPnL: Decimal
        let pnlSource: ScreenshotImportTradeMetadata.PnLSource
        if let reported = pnlEval.reportedPnL {
            realizedPnL = reported
            if let calculated = pnlEval.calculatedGrossPnL {
                pnlSource = warnings.contains("Review P&L") ? .reportedAndCalculated : .reported
                _ = calculated
            } else {
                pnlSource = .reported
            }
        } else if let calculated = pnlEval.calculatedGrossPnL {
            realizedPnL = calculated
            pnlSource = .calculated
            if !warnings.contains(where: { $0.contains("P&L") }) {
                warnings.append("Calculated from executions")
            }
        } else {
            realizedPnL = 0
            pnlSource = .reported
            if !warnings.contains("P&L missing") {
                warnings.append("P&L missing")
            }
        }

        let executionIDs = (trip.entryFills + trip.exitFills).compactMap(\.executionID)
        let orderIDs = (trip.entryFills + trip.exitFills).compactMap(\.orderID)
        let fingerprint = ImportFingerprint.forAggregatedTrade(
            symbol: trip.symbol,
            side: trip.side,
            quantity: trip.quantity,
            entryPrice: trip.entryPrice,
            exitPrice: trip.exitPrice,
            entryAt: trip.entryAt,
            exitAt: trip.exitAt,
            accountID: accountID,
            executionIDs: executionIDs,
            orderIDs: orderIDs
        )

        let durationSeconds = TradeHoldDuration.compute(entryAt: trip.entryAt, exitAt: trip.exitAt)?.seconds
        let status: CSVTradeParseStatus = warnings.isEmpty ? .ready : .needsReview
        let tradeID = "agg-\(fingerprint.suffix(12))"

        let trade = CSVParsedTrade(
            id: tradeID,
            rowNumber: rowNumber,
            symbol: trip.symbol,
            side: trip.side,
            quantity: trip.quantity,
            entryPrice: trip.entryPrice,
            exitPrice: trip.exitPrice,
            entryAt: trip.entryAt,
            exitAt: trip.exitAt,
            realizedPnL: realizedPnL,
            riskReward: nil,
            points: points,
            sessionLabel: TradingSessionLabel.session(from: trip.entryAt),
            notes: notes,
            strategy: nil,
            csvAccountName: nil,
            csvAccountID: nil,
            csvAccountSize: nil,
            durationSeconds: durationSeconds,
            status: status,
            warningMessages: warnings
        )

        let metadata = ScreenshotImportTradeMetadata(
            fills: trip.entryFills + trip.exitFills,
            entryFillCount: trip.entryFills.count,
            exitFillCount: trip.exitFills.count,
            aggregationSource: .fillAggregation,
            reportedPnL: pnlEval.reportedPnL,
            calculatedPnL: pnlEval.calculatedGrossPnL,
            pnlSource: pnlSource,
            aggregatedFees: trip.aggregatedFees > 0 ? trip.aggregatedFees : nil,
            importFingerprint: fingerprint,
            duplicateClassification: .newTrade,
            isSelectedForImport: true,
            warnings: warnings,
            extractionSource: .deterministic
        )

        return (trade, metadata)
    }
}
