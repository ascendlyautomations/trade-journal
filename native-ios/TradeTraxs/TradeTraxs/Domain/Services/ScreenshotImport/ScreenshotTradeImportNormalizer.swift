import Foundation

/// Converts screenshot candidates into `CSVParsedTrade` with review status and derived fields.
nonisolated enum ScreenshotTradeImportNormalizer {
    static func normalize(
        parseResult: ScreenshotImportParseResult,
        dedupedCandidates: [ScreenshotParsedCandidate]
    ) -> CSVParseSummary {
        var trades: [CSVParsedTrade] = []
        var rowNumber = 1

        for candidate in dedupedCandidates {
            if let trade = normalizeCandidate(candidate, rowNumber: rowNumber) {
                trades.append(trade)
                rowNumber += 1
            }
        }

        let successCount = trades.filter(\.isImportable).count
        return CSVParseSummary(
            format: .screenshot,
            fileName: "screenshot-import",
            totalRows: parseResult.candidates.count,
            successCount: successCount,
            failedCount: parseResult.failures.count + (parseResult.candidates.count - dedupedCandidates.count),
            headers: [],
            trades: trades,
            failures: parseResult.failures
        )
    }

    static func normalizeCandidate(
        _ candidate: ScreenshotParsedCandidate,
        rowNumber: Int
    ) -> CSVParsedTrade? {
        if candidate.kind == .executionFill {
            return normalizeExecutionFill(candidate, rowNumber: rowNumber)
        }
        return normalizeCompletedTrade(candidate, rowNumber: rowNumber)
    }

    private static func normalizeExecutionFill(
        _ candidate: ScreenshotParsedCandidate,
        rowNumber: Int
    ) -> CSVParsedTrade? {
        guard let symbol = candidate.symbol, !symbol.isEmpty else { return nil }
        let side = candidate.side ?? .long
        let warnings = candidate.warnings + ["Could be individual executions"]
        return CSVParsedTrade(
            id: candidate.id,
            rowNumber: rowNumber,
            symbol: symbol,
            side: side,
            quantity: candidate.quantity ?? 1,
            entryPrice: candidate.entryPrice,
            exitPrice: candidate.exitPrice,
            entryAt: candidate.entryAt ?? Date(),
            exitAt: candidate.exitAt,
            realizedPnL: candidate.realizedPnL ?? 0,
            riskReward: nil,
            points: candidate.points,
            sessionLabel: TradingSessionLabel.session(from: candidate.entryAt ?? Date()),
            notes: "",
            strategy: nil,
            csvAccountName: nil,
            csvAccountID: nil,
            csvAccountSize: nil,
            durationSeconds: nil,
            status: .needsReview,
            warningMessages: warnings
        )
    }

    private static func normalizeCompletedTrade(
        _ candidate: ScreenshotParsedCandidate,
        rowNumber: Int
    ) -> CSVParsedTrade? {
        guard let symbol = candidate.symbol?.trimmingCharacters(in: .whitespacesAndNewlines),
              !symbol.isEmpty
        else { return nil }

        let side = candidate.side ?? .long
        var entryAt = candidate.entryAt ?? Date()
        var exitAt = candidate.exitAt
        var entryPrice = candidate.entryPrice
        var exitPrice = candidate.exitPrice

        if let exit = exitAt, exit < entryAt {
            let correctedEntry = exit
            let correctedExit = entryAt
            entryAt = correctedEntry
            exitAt = correctedExit
            swap(&entryPrice, &exitPrice)
        }

        var warnings = candidate.warnings
        var points = candidate.points

        if points == nil, let entryPrice, let exitPrice {
            points = directionalPoints(side: side, entry: entryPrice, exit: exitPrice)
        }

        var durationSeconds: Int?
        if let exitAt, let duration = TradeHoldDuration.compute(entryAt: entryAt, exitAt: exitAt) {
            durationSeconds = duration.seconds
        } else if exitAt == nil {
            warnings.append("Confirm date")
        }

        let pnl = candidate.realizedPnL
        if pnl == nil {
            warnings.append("P&L missing")
        }

        if entryPrice == nil {
            warnings.append("Review entry price")
        }
        if exitPrice == nil {
            warnings.append("Review exit price")
        }

        if isFuture(entryAt) || (exitAt.map(isFuture) == true) {
            warnings.append("Confirm date")
        }

        let status: CSVTradeParseStatus = warnings.isEmpty ? .ready : .needsReview

        return CSVParsedTrade(
            id: candidate.id,
            rowNumber: rowNumber,
            symbol: symbol,
            side: side,
            quantity: candidate.quantity ?? 1,
            entryPrice: entryPrice,
            exitPrice: exitPrice,
            entryAt: entryAt,
            exitAt: exitAt,
            realizedPnL: pnl ?? 0,
            riskReward: nil,
            points: points,
            sessionLabel: TradingSessionLabel.session(from: entryAt),
            notes: "",
            strategy: nil,
            csvAccountName: nil,
            csvAccountID: nil,
            csvAccountSize: nil,
            durationSeconds: durationSeconds,
            status: status,
            warningMessages: warnings
        )
    }

    private static func directionalPoints(side: TradeSide, entry: Decimal, exit: Decimal) -> Decimal {
        side == .short ? entry - exit : exit - entry
    }

    private static func isFuture(_ date: Date) -> Bool {
        date.timeIntervalSinceNow > 60
    }
}
