import Foundation

/// Journal-wide duplicate detection for import candidates.
nonisolated enum ImportDuplicateDetector {
    struct CandidateContext {
        var trade: CSVParsedTrade
        var fingerprint: String?
        var metadata: ScreenshotImportTradeMetadata
    }

    static func classify(
        candidate: CandidateContext,
        existingTrades: [Trade],
        accountID: TradingAccountID?
    ) -> ImportDuplicateClassification {
        if let fingerprint = candidate.fingerprint,
           existingTrades.contains(where: {
               $0.importFingerprint == fingerprint && $0.accountID == accountID
           })
        {
            return .exactDuplicate
        }

        if existingTrades.contains(where: {
            fuzzyMatch(candidate.trade, existing: $0, accountID: accountID)
        }) {
            return .possibleDuplicate
        }

        return .newTrade
    }

    static func applyClassification(
        to metadata: inout ScreenshotImportTradeMetadata,
        classification: ImportDuplicateClassification
    ) {
        metadata.duplicateClassification = classification
        metadata.isSelectedForImport = classification != .exactDuplicate
        if let label = classification.reviewLabel,
           !metadata.warnings.contains(label)
        {
            metadata.warnings.append(label)
        }
    }

    private static func fuzzyMatch(
        _ candidate: CSVParsedTrade,
        existing: Trade,
        accountID: TradingAccountID?
    ) -> Bool {
        guard existing.accountID == accountID else { return false }
        guard FuturesInstrumentRegistry.normalizeSymbol(existing.symbol.ticker)
            == FuturesInstrumentRegistry.normalizeSymbol(candidate.symbol)
        else { return false }

        let existingDate = TradingSessionLabel.easternTradeDateString(from: existing.entryAt)
        let candidateDate = TradingSessionLabel.easternTradeDateString(from: candidate.entryAt)
        guard existingDate == candidateDate else { return false }

        if abs(existing.entryAt.timeIntervalSince1970 - candidate.entryAt.timeIntervalSince1970) <= 120 {
            if decimalClose(existing.quantity, candidate.quantity),
               decimalClose(existing.entryPrice, candidate.entryPrice),
               decimalClose(existing.exitPrice, candidate.exitPrice),
               decimalClose(existing.realizedPnL?.amount, candidate.realizedPnL)
            {
                return true
            }
        }
        return false
    }

    private static func decimalClose(_ lhs: Decimal?, _ rhs: Decimal?, tolerance: Decimal = 1) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (l?, r?): return abs(l - r) <= tolerance
        default: return false
        }
    }
}
