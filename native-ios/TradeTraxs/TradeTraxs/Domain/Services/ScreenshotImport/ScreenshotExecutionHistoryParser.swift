import Foundation

/// Parses order/execution history rows into fills for Phase 2 aggregation.
nonisolated enum ScreenshotExecutionHistoryParser {
    struct Result: Hashable, Sendable {
        var fills: [ParsedTradeFill]
        var ignoredCancelledRows: Int
        var rejectedRows: [ScreenshotImportRejectedRow]
    }

    static func parse(tables: [ScreenshotStructuredTable]) -> Result {
        var fills: [ParsedTradeFill] = []
        var ignoredCancelled = 0
        var rejected: [ScreenshotImportRejectedRow] = []
        var fillIndex = 0

        for table in tables {
            for row in table.dataRows {
                switch parseRow(row, fillIndex: fillIndex) {
                case .fill(let fill):
                    fills.append(fill)
                    fillIndex += 1
                case .ignoredCancelled:
                    ignoredCancelled += 1
                case .rejected(let reason):
                    rejected.append(ScreenshotImportRejectedRow(rowIndex: row.id, reason: reason))
                case .skipped:
                    break
                }
            }
        }
        return Result(fills: fills, ignoredCancelledRows: ignoredCancelled, rejectedRows: rejected)
    }

    private enum RowOutcome {
        case fill(ParsedTradeFill)
        case ignoredCancelled
        case rejected(String)
        case skipped
    }

    private static func parseRow(_ row: ScreenshotStructuredRow, fillIndex: Int) -> RowOutcome {
        let cells = row.allCellTexts
        let joined = cells.joined(separator: " ")

        let status = row.value(for: .status) ?? cells.first(where: { ScreenshotBrokerText.isExecutionStatus($0) })
        if let status, ScreenshotBrokerText.isNonFillStatus(status) {
            return .ignoredCancelled
        }
        if cells.contains(where: {
            ScreenshotBrokerText.isTriggerAction($0) &&
                !joined.uppercased().contains("FILLED") &&
                !joined.uppercased().contains("ALLED")
        }) {
            if status == nil || !ScreenshotBrokerText.isFilledStatus(status ?? "") {
                if cells.contains(where: { $0.uppercased().contains("CANCEL") || ($0.lowercased().contains("oco") && $0.lowercased().contains("pull")) }) {
                    return .ignoredCancelled
                }
            }
        }

        let isFilled = status.map { ScreenshotBrokerText.isFilledStatus($0) } ?? inferFilled(from: cells)
        guard isFilled else {
            if cells.contains(where: { ScreenshotBrokerText.isNonFillStatus($0) }) {
                return .ignoredCancelled
            }
            return .skipped
        }

        guard let symbolRaw = row.value(for: .symbol) ?? cells.compactMap({ ScreenshotBrokerText.extractSymbol(from: $0) }).first,
              let symbol = ScreenshotBrokerText.extractSymbol(from: symbolRaw)
              ?? Optional(ScreenshotBrokerText.normalizeSymbol(symbolRaw))
        else {
            return .rejected("Missing symbol")
        }

        let sideToken = row.value(for: .side) ?? cells.first(where: { ScreenshotBrokerText.isBuySell($0) })
        guard let sideToken, ScreenshotBrokerText.isBuySell(sideToken) else {
            return .rejected("Missing BUY/SELL side")
        }
        let action: ParsedTradeFill.Action = sideToken.uppercased().hasPrefix("S") ? .sell : .buy

        guard let price = extractExecutionPrice(from: row, cells: cells) else {
            return .rejected("Missing execution price")
        }

        let quantity = extractQuantity(from: row, cells: cells) ?? 1
        let executedAt = extractTimestamp(from: row, cells: cells) ?? Date()

        var warnings: [String] = []
        if executedAt == Date() { warnings.append("Confirm date") }
        if row.value(for: .side) == nil { warnings.append("Confirm side") }

        let fill = ParsedTradeFill(
            id: "exec-fill-\(fillIndex)",
            symbol: symbol,
            action: action,
            quantity: quantity,
            price: price,
            executedAt: executedAt,
            reportedPnL: nil,
            commission: nil,
            executionID: row.value(for: .executionID),
            orderID: row.value(for: .orderID),
            sourcePlatform: .generic,
            sourceImageIndex: row.sourceImageIndex,
            sourceRowIndex: row.id,
            warnings: warnings
        )
        return .fill(fill)
    }

    private static func inferFilled(from cells: [String]) -> Bool {
        cells.contains(where: { ScreenshotBrokerText.isFilledStatus($0) })
    }

    private static func extractExecutionPrice(from row: ScreenshotStructuredRow, cells: [String]) -> Decimal? {
        if let raw = row.value(for: .price), let parsed = CSVNumericParser.parse(raw), parsed > 0 {
            return parsed
        }
        let decimals = cells.compactMap { cell -> Decimal? in
            guard !ScreenshotBrokerText.isBuySell(cell),
                  !ScreenshotBrokerText.isOrderType(cell),
                  !ScreenshotBrokerText.isExecutionStatus(cell),
                  !ScreenshotBrokerText.isTimestamp(cell),
                  !ScreenshotBrokerText.isTriggerAction(cell),
                  let value = CSVNumericParser.parse(cell),
                  value > 0
            else { return nil }
            if value >= 100 || cell.contains(".") || cell.contains(",") { return value }
            return nil
        }
        return decimals.max(by: { $0 < $1 })
    }

    private static func extractQuantity(from row: ScreenshotStructuredRow, cells: [String]) -> Decimal? {
        if let raw = row.value(for: .filledQuantity) ?? row.value(for: .volume),
           let parsed = CSVNumericParser.parse(raw),
           parsed > 0, parsed <= 1000
        {
            return parsed
        }

        let qtyCandidates = cells.compactMap { cell -> Decimal? in
            guard let value = CSVNumericParser.parse(cell), value > 0, value <= 1000 else { return nil }
            if ScreenshotBrokerText.isTimestamp(cell) { return nil }
            if value > 10_000 { return nil }
            return value
        }
        return qtyCandidates.last ?? qtyCandidates.first
    }

    private static func extractTimestamp(from row: ScreenshotStructuredRow, cells: [String]) -> Date? {
        if let raw = row.value(for: .timestamp) ?? row.value(for: .openTime) {
            if let parsed = ScreenshotDateTimeParser.parse(raw) { return parsed }
        }
        for cell in cells where ScreenshotBrokerText.isTimestamp(cell) {
            if let parsed = ScreenshotDateTimeParser.parse(cell) { return parsed }
        }
        return nil
    }
}
