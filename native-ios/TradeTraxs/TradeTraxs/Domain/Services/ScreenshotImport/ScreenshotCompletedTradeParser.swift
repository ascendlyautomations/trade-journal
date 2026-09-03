import Foundation

/// Parses completed-trade table layouts (one row = one round-trip trade).
nonisolated enum ScreenshotCompletedTradeParser {
    struct Result: Hashable, Sendable {
        var candidates: [ScreenshotParsedCandidate]
        var rejectedRows: [ScreenshotImportRejectedRow]
    }

    static func parse(tables: [ScreenshotStructuredTable]) -> Result {
        var candidates: [ScreenshotParsedCandidate] = []
        var rejected: [ScreenshotImportRejectedRow] = []
        var candidateIndex = 0

        for table in tables {
            for row in table.dataRows {
                if isSensitiveMetadataRow(row) { continue }
                switch parseRow(row, candidateIndex: candidateIndex) {
                case .candidate(let candidate):
                    candidates.append(candidate)
                    candidateIndex += 1
                case .rejected(let reason):
                    rejected.append(ScreenshotImportRejectedRow(rowIndex: row.id, reason: reason))
                case .skipped:
                    break
                }
            }
        }
        return Result(candidates: candidates, rejectedRows: rejected)
    }

    private enum RowOutcome {
        case candidate(ScreenshotParsedCandidate)
        case rejected(String)
        case skipped
    }

    private static func isSensitiveMetadataRow(_ row: ScreenshotStructuredRow) -> Bool {
        let joined = row.allCellTexts.joined(separator: " ").lowercased()
        return joined.contains("account id") && joined.contains("username")
    }

    private static func parseRow(_ row: ScreenshotStructuredRow, candidateIndex: Int) -> RowOutcome {
        let symbolRaw = row.value(for: .symbol) ?? row.allCellTexts.compactMap { ScreenshotBrokerText.extractSymbol(from: $0) }.first
        guard let symbolRaw,
              let symbol = ScreenshotBrokerText.extractSymbol(from: symbolRaw) ??
              Optional(ScreenshotBrokerText.normalizeSymbol(symbolRaw)),
              !symbol.isEmpty
        else {
            return .rejected("Missing symbol")
        }

        let side = parseTradeSide(from: row)
        var warnings: [String] = []
        if side == nil { warnings.append("Confirm direction") }
        let resolvedSide = side ?? .long

        let quantity = parseVolume(row) ?? 1
        let entryPrice = CSVNumericParser.parse(row.value(for: .openPrice))
        let exitPrice = CSVNumericParser.parse(row.value(for: .closePrice))
        let pnl = CSVNumericParser.parse(row.value(for: .pnl))
        let fees = CSVNumericParser.parse(row.value(for: .fees))

        let entryAt = ScreenshotDateTimeParser.parse(row.value(for: .openTime))
            ?? ScreenshotDateTimeParser.parse(row.value(for: .tradeDay))
            ?? inferTimestamp(from: row.allCellTexts, role: .entry)
        let exitAt = ScreenshotDateTimeParser.parse(row.value(for: .closeTime))
            ?? inferTimestamp(from: row.allCellTexts, role: .exit)

        if pnl == nil { warnings.append("P&L missing") }
        if entryPrice == nil { warnings.append("Review entry price") }
        if exitPrice == nil { warnings.append("Review exit price") }
        if entryAt == nil { warnings.append("Confirm date") }
        if fees != nil && pnl != nil {
            // Fees are tracked separately; do not adjust reported P&L.
        }

        var points: Decimal?
        if let entryPrice, let exitPrice {
            points = FuturesInstrumentRegistry.directionalPoints(side: resolvedSide, entry: entryPrice, exit: exitPrice)
        }

        if entryPrice == nil && exitPrice == nil && pnl == nil {
            return .skipped
        }

        return .candidate(
            ScreenshotParsedCandidate(
                id: "completed-\(candidateIndex)",
                kind: .completedTrade,
                symbol: symbol,
                side: resolvedSide,
                quantity: quantity,
                entryPrice: entryPrice,
                exitPrice: exitPrice,
                entryAt: entryAt ?? Date(),
                exitAt: exitAt,
                realizedPnL: pnl,
                points: points,
                executionID: row.value(for: .tradeID),
                orderID: row.value(for: .orderID),
                warnings: warnings,
                sourceImageIndex: row.sourceImageIndex,
                sourceRowIndex: row.id
            )
        )
    }

    private static func parseTradeSide(from row: ScreenshotStructuredRow) -> TradeSide? {
        if let explicit = row.value(for: .side), ScreenshotBrokerText.isLongShort(explicit) {
            return ScreenshotBrokerText.parseDirection(explicit)
        }
        for cell in row.allCellTexts where ScreenshotBrokerText.isLongShort(cell) {
            return ScreenshotBrokerText.parseDirection(cell)
        }
        if let mappedSide = row.value(for: .side) {
            return ScreenshotBrokerText.parseDirection(mappedSide)
        }
        return ScreenshotBrokerText.parsePosition(row.value(for: .position))
            ?? ScreenshotBrokerText.parseSideFromOpenSide(row.value(for: .openSide))
    }

    private static func parseVolume(_ row: ScreenshotStructuredRow) -> Decimal? {
        if let raw = row.value(for: .volume), let parsed = CSVNumericParser.parse(raw), !looksLikeDate(raw) {
            return parsed
        }
        for cell in row.allCellTexts {
            if looksLikeDate(cell) { continue }
            if let parsed = CSVNumericParser.parse(cell), parsed > 0, parsed <= 1000, !cell.contains("$") {
                return parsed
            }
        }
        return nil
    }

    private static func looksLikeDate(_ raw: String) -> Bool {
        raw.range(of: #"\d{1,2}-\d{1,2}-\d{4}"#, options: .regularExpression) != nil
            || raw.range(of: #"\d{1,2}/\d{1,2}/\d{4}"#, options: .regularExpression) != nil
    }

    private enum TimestampRole { case entry, exit }

    private static func inferTimestamp(from cells: [String], role: TimestampRole) -> Date? {
        let timestamps = cells.compactMap { ScreenshotDateTimeParser.parse($0) }
        guard !timestamps.isEmpty else { return nil }
        switch role {
        case .entry: return timestamps.min()
        case .exit: return timestamps.max()
        }
    }
}
