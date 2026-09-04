import Foundation

/// Deterministic trade / execution parsing from reconstructed screenshot rows.
nonisolated enum ScreenshotTradeParser {
    private enum Column: String, CaseIterable {
        case symbol
        case side
        case quantity
        case entryPrice
        case exitPrice
        case pnl
        case points
        case date
        case entryTime
        case exitTime
        case orderID
        case executionID
    }

    static func parse(rows: [ScreenshotTableRow]) -> ScreenshotImportParseResult {
        var candidates: [ScreenshotParsedCandidate] = []
        var failures: [CSVParseRowFailure] = []
        var candidateIndex = 0

        let (headerIndex, columnMap) = detectHeader(in: rows)
        let dataRows: [ScreenshotTableRow]
        if let headerIndex, !columnMap.isEmpty {
            dataRows = Array(rows.dropFirst(headerIndex + 1))
        } else {
            dataRows = rows
        }

        for row in dataRows {
            if isHeaderLike(row.cells) { continue }

            if let execution = parseExecutionLine(row.cells.joined(separator: " "), row: row) {
                candidates.append(execution)
                candidateIndex += 1
                continue
            }

            if let mapped = parseMappedRow(
                row: row,
                columnMap: columnMap,
                candidateIndex: candidateIndex
            ) {
                candidates.append(mapped)
                candidateIndex += 1
                continue
            }

            if let freeform = parseFreeformLine(
                row.cells.joined(separator: " "),
                row: row,
                candidateIndex: candidateIndex
            ) {
                candidates.append(freeform)
                candidateIndex += 1
                continue
            }

            if row.cells.count >= 2 {
                failures.append(
                    CSVParseRowFailure(
                        rowNumber: row.id + 1,
                        reason: "Couldn't parse row: \(row.cells.prefix(4).joined(separator: " · "))"
                    )
                )
            }
        }

        return ScreenshotImportParseResult(
            candidates: candidates,
            failures: failures,
            imagesProcessed: Set(rows.map(\.sourceImageIndex)).count
        )
    }

    // MARK: - Header detection

    private static func detectHeader(in rows: [ScreenshotTableRow]) -> (Int?, [Column: Int]) {
        for (index, row) in rows.prefix(8).enumerated() {
            var map: [Column: Int] = [:]
            for (cellIndex, cell) in row.cells.enumerated() {
                if let column = classifyHeader(cell) {
                    map[column] = cellIndex
                }
            }
            if map.count >= 2 {
                return (index, map)
            }
        }
        return (nil, [:])
    }

    private static func classifyHeader(_ raw: String) -> Column? {
        let s = raw.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if matches(s, any: ["entry time", "open time", "entered", "time in"]) {
            return .entryTime
        }
        if matches(s, any: ["exit time", "close time", "exited", "time out"]) {
            return .exitTime
        }
        if matches(s, any: ["symbol", "sym", "ticker", "instrument", "contract", "product", "market"]) {
            return .symbol
        }
        if matches(s, any: ["side", "direction", "type", "b/s", "buy/sell"]) {
            return .side
        }
        if matches(s, any: ["qty", "quantity", "contracts", "size", "filled", "fill qty"]) {
            return .quantity
        }
        if matches(s, any: ["entry price", "buy price", "open price", "avg entry", "entry px"]) {
            return .entryPrice
        }
        if matches(s, any: ["exit price", "sell price", "close price", "avg exit", "exit px"]) {
            return .exitPrice
        }
        if s == "entry" || s == "exit" {
            return s == "entry" ? .entryPrice : .exitPrice
        }
        if matches(s, any: ["p&l", "pnl", "p/l", "profit", "net p&l", "realized", "net"]) && !s.contains("open") {
            return .pnl
        }
        if matches(s, any: ["points", "pts", "point"]) {
            return .points
        }
        if matches(s, any: ["date", "trade date", "day"]) {
            return .date
        }
        if matches(s, any: ["order id", "order #", "order no", "order"]) {
            return .orderID
        }
        if matches(s, any: ["exec id", "execution id", "fill id", "execution"]) {
            return .executionID
        }
        return nil
    }

    private static func isHeaderLike(_ cells: [String]) -> Bool {
        let joined = cells.joined(separator: " ").lowercased()
        let hits = [
            "symbol", "ticker", "direction", "entry", "exit", "p&l", "pnl", "qty", "contracts",
        ].filter { joined.contains($0) }.count
        return hits >= 2
    }

    // MARK: - Row parsers

    private static func parseMappedRow(
        row: ScreenshotTableRow,
        columnMap: [Column: Int],
        candidateIndex: Int
    ) -> ScreenshotParsedCandidate? {
        guard !columnMap.isEmpty else { return nil }

        func cell(_ column: Column) -> String? {
            guard let index = columnMap[column], index < row.cells.count else { return nil }
            let value = row.cells[index].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }

        let symbolRaw = cell(.symbol) ?? inferSymbol(from: row.cells)
        guard let symbolRaw, !symbolRaw.isEmpty else { return nil }

        let side = normalizeDirection(cell(.side))
            ?? ScreenshotBrokerText.parseSideFromOpenSide(cell(.side))
            ?? .long

        let quantity = CSVNumericParser.parse(cell(.quantity)) ?? 1
        let entryPrice = CSVNumericParser.parse(cell(.entryPrice))
        let exitPrice = CSVNumericParser.parse(cell(.exitPrice))
        let pnl = CSVNumericParser.parse(cell(.pnl))
        let points = CSVNumericParser.parse(cell(.points))
        let orderID = cell(.orderID)
        let executionID = cell(.executionID)

        let dateSeed = cell(.date)
        let entryAt = composeDateTime(date: dateSeed, time: cell(.entryTime))
            ?? composeDateTime(date: dateSeed, time: nil)
            ?? Date()
        let exitAt = composeDateTime(date: dateSeed, time: cell(.exitTime))

        var warnings: [String] = []
        if pnl == nil { warnings.append("P&L missing") }
        if entryPrice == nil { warnings.append("Review entry price") }
        if exitPrice == nil { warnings.append("Review exit price") }
        if columnMap[.side] == nil {
            warnings.append("Confirm direction")
        }

        return ScreenshotParsedCandidate(
            id: "candidate-\(candidateIndex)",
            kind: .completedTrade,
            symbol: normalizeFuturesSymbol(symbolRaw),
            side: side,
            quantity: quantity,
            entryPrice: entryPrice,
            exitPrice: exitPrice,
            entryAt: entryAt,
            exitAt: exitAt,
            realizedPnL: pnl,
            points: points,
            executionID: executionID,
            orderID: orderID,
            warnings: warnings,
            sourceImageIndex: row.sourceImageIndex,
            sourceRowIndex: row.id
        )
    }

    private static func parseExecutionLine(
        _ line: String,
        row: ScreenshotTableRow
    ) -> ScreenshotParsedCandidate? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let nsRange = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = executionRegex.firstMatch(in: trimmed, range: nsRange) else { return nil }

        guard let sideRange = Range(match.range(at: 1), in: trimmed) else { return nil }
        let sideToken = String(trimmed[sideRange]).uppercased()

        func group(_ index: Int) -> String? {
            guard let range = Range(match.range(at: index), in: trimmed) else { return nil }
            return String(trimmed[range])
        }

        guard let qtyRaw = group(2),
              let symbolRaw = group(3),
              let priceRaw = group(4),
              let quantity = CSVNumericParser.parse(qtyRaw),
              let price = CSVNumericParser.parse(priceRaw)
        else { return nil }

        let side: TradeSide = sideToken.hasPrefix("S") ? .short : .long

        return ScreenshotParsedCandidate(
            id: "exec-\(row.id)",
            kind: .executionFill,
            symbol: normalizeFuturesSymbol(symbolRaw),
            side: side,
            quantity: quantity,
            entryPrice: side == .long ? price : nil,
            exitPrice: side == .short ? price : nil,
            entryAt: Date(),
            exitAt: nil,
            realizedPnL: nil,
            points: nil,
            executionID: nil,
            orderID: nil,
            warnings: ["Could be individual executions"],
            sourceImageIndex: row.sourceImageIndex,
            sourceRowIndex: row.id
        )
    }

    private static func parseFreeformLine(
        _ line: String,
        row: ScreenshotTableRow,
        candidateIndex: Int
    ) -> ScreenshotParsedCandidate? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { return nil }

        guard let symbol = inferSymbol(from: [trimmed]) ?? extractSymbol(from: trimmed) else {
            return nil
        }

        let side = normalizeDirection(trimmed) ?? .long
        let numbers = extractNumbers(from: trimmed)
        guard numbers.count >= 2 else { return nil }

        var entryPrice: Decimal?
        var exitPrice: Decimal?
        var pnl: Decimal?
        var quantity: Decimal = 1

        if let pnlRange = trimmed.lowercased().range(of: "p&l") ?? trimmed.lowercased().range(of: "pnl") {
            let tail = String(trimmed[pnlRange.upperBound...])
            pnl = CSVNumericParser.parse(tail.components(separatedBy: " ").first ?? "")
        }

        if numbers.count >= 4 {
            quantity = numbers[0]
            entryPrice = numbers[1]
            exitPrice = numbers[2]
            if pnl == nil { pnl = numbers[3] }
        } else if numbers.count == 3 {
            entryPrice = numbers[0]
            exitPrice = numbers[1]
            if pnl == nil { pnl = numbers[2] }
        } else {
            entryPrice = numbers[0]
            exitPrice = numbers[1]
        }

        let inferredSide = normalizeDirection(trimmed) ?? side

        var warnings: [String] = []
        if pnl == nil { warnings.append("P&L missing") }
        if entryPrice == nil { warnings.append("Review entry price") }
        if exitPrice == nil { warnings.append("Review exit price") }

        return ScreenshotParsedCandidate(
            id: "freeform-\(candidateIndex)",
            kind: .completedTrade,
            symbol: symbol,
            side: inferredSide,
            quantity: quantity,
            entryPrice: entryPrice,
            exitPrice: exitPrice,
            entryAt: Date(),
            exitAt: nil,
            realizedPnL: pnl,
            points: nil,
            executionID: nil,
            orderID: nil,
            warnings: warnings,
            sourceImageIndex: row.sourceImageIndex,
            sourceRowIndex: row.id
        )
    }

    // MARK: - Helpers

    private static let executionRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"^(BUY|SELL|BOT|SLD)\s+(\d+)\s+([A-Z][A-Z0-9]{1,5})\s*[@]\s*([\d,]+(?:\.\d+)?)"#,
            options: [.caseInsensitive]
        )
    }()

    private static func matches(_ haystack: String, any needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    private static func normalizeDirection(_ raw: String?) -> TradeSide? {
        guard let raw else { return nil }
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty { return nil }
        if ["long", "buy", "b", "bull", "bot"].contains(s) || s.contains("long") || s.contains("buy") {
            return .long
        }
        if ["short", "sell", "s", "ss", "bear", "sld"].contains(s) || s.contains("short") || s.contains("sell") {
            return .short
        }
        return nil
    }

    private static func inferSide(entry: Decimal?, exit: Decimal?) -> TradeSide? {
        guard let entry, let exit, entry != exit else { return nil }
        return exit > entry ? .long : .short
    }

    private static func normalizeFuturesSymbol(_ raw: String) -> String {
        FuturesInstrumentRegistry.normalizeSymbol(raw)
    }

    private static func inferSymbol(from cells: [String]) -> String? {
        for cell in cells {
            let token = cell.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if token.range(of: #"^[A-Z][A-Z0-9]{0,5}$"#, options: .regularExpression) != nil,
               !["LONG", "SHORT", "BUY", "SELL", "DATE", "TOTAL"].contains(token)
            {
                return normalizeFuturesSymbol(token)
            }
        }
        return nil
    }

    private static func extractSymbol(from line: String) -> String? {
        let upper = line.uppercased()
        let pattern = #"\b([A-Z][A-Z0-9]{1,5})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(upper.startIndex..., in: upper)
        let matches = regex.matches(in: upper, range: range)
        for match in matches {
            guard let r = Range(match.range(at: 1), in: upper) else { continue }
            let token = String(upper[r])
            if !["LONG", "SHORT", "BUY", "SELL"].contains(token) {
                return normalizeFuturesSymbol(token)
            }
        }
        return nil
    }

    private static func extractNumbers(from line: String) -> [Decimal] {
        let pattern = #"[\(]?[-+]?\$?\d[\d,]*(?:\.\d+)?[\)]?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(line.startIndex..., in: line)
        return regex.matches(in: line, range: nsRange).compactMap { match -> Decimal? in
            guard let range = Range(match.range, in: line) else { return nil }
            return CSVNumericParser.parse(String(line[range]))
        }
    }

    private static func composeDateTime(date: String?, time: String?) -> Date? {
        if let date, let time, let combined = parseDateTime("\(date) \(time)") {
            return combined
        }
        if let date, let parsed = parseDate(date) {
            return parsed
        }
        if let time, let parsed = parseTimeToday(time) {
            return parsed
        }
        return nil
    }

    private static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let formats = [
            "yyyy-MM-dd", "MM/dd/yyyy", "M/d/yyyy", "MMM d, yyyy", "MMM d yyyy",
            "yyyy/MM/dd", "dd/MM/yyyy",
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "America/New_York")
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }

    private static func parseDateTime(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let formats = [
            "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "MM/dd/yyyy HH:mm:ss", "MM/dd/yyyy HH:mm",
            "MMM d, yyyy HH:mm", "yyyy-MM-dd h:mm a", "MM/dd/yyyy h:mm a",
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "America/New_York")
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        return parseDate(trimmed)
    }

    private static func parseTimeToday(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let formats = ["HH:mm:ss", "HH:mm", "h:mm a", "h:mm:ss a"]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        let today = calendar.startOfDay(for: Date())
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = format
            if let time = formatter.date(from: trimmed) {
                let parts = calendar.dateComponents([.hour, .minute, .second], from: time)
                return calendar.date(byAdding: parts, to: today)
            }
        }
        return nil
    }
}
