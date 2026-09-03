import Foundation

/// Converts reconstructed rows into `ParsedTradeFill` records.
nonisolated enum ScreenshotGenericFillParser {
    private enum Column: String {
        case symbol, side, quantity, price, pnl, commission, date, time, executionID, orderID, action
    }

    static func parse(
        rows: [ScreenshotTableRow],
        platform: ScreenshotImportPlatform = .generic
    ) -> [ParsedTradeFill] {
        var fills: [ParsedTradeFill] = []
        let (headerIndex, columnMap) = detectHeader(in: rows)
        let dataRows = headerIndex.map { Array(rows.dropFirst($0 + 1)) } ?? rows

        for row in dataRows {
            if isHeaderLike(row.cells) { continue }

            let line = row.cells.joined(separator: " ")
            if let execution = parseExecutionLine(line, row: row, platform: platform) {
                fills.append(execution)
                continue
            }

            if let mapped = parseMappedFill(row: row, columnMap: columnMap, platform: platform) {
                fills.append(mapped)
            }
        }
        return fills
    }

    private static func detectHeader(in rows: [ScreenshotTableRow]) -> (Int?, [Column: Int]) {
        for (index, row) in rows.prefix(8).enumerated() {
            var map: [Column: Int] = [:]
            for (cellIndex, cell) in row.cells.enumerated() {
                if let column = classifyHeader(cell) {
                    map[column] = cellIndex
                }
            }
            if map.count >= 2 { return (index, map) }
        }
        return (nil, [:])
    }

    private static func classifyHeader(_ raw: String) -> Column? {
        let s = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if matches(s, any: ["time", "timestamp", "executed"]) && !s.contains("entry") && !s.contains("exit") {
            return .time
        }
        if matches(s, any: ["symbol", "sym", "ticker", "contract", "product"]) { return .symbol }
        if matches(s, any: ["side", "direction", "b/s", "buy/sell", "action"]) { return .action }
        if matches(s, any: ["qty", "quantity", "contracts", "size", "filled"]) { return .quantity }
        if matches(s, any: ["price", "fill price", "avg price", "execution price"]) { return .price }
        if matches(s, any: ["p&l", "pnl", "profit", "net"]) && !s.contains("open") { return .pnl }
        if matches(s, any: ["commission", "comm", "fee", "fees"]) { return .commission }
        if matches(s, any: ["date", "trade date", "day"]) { return .date }
        if matches(s, any: ["exec id", "execution id", "fill id"]) { return .executionID }
        if matches(s, any: ["order id", "order #", "order"]) { return .orderID }
        return nil
    }

    private static func isHeaderLike(_ cells: [String]) -> Bool {
        let joined = cells.joined(separator: " ").lowercased()
        return ["symbol", "qty", "price", "p&l", "pnl", "side"].filter { joined.contains($0) }.count >= 2
    }

    private static func parseMappedFill(
        row: ScreenshotTableRow,
        columnMap: [Column: Int],
        platform: ScreenshotImportPlatform
    ) -> ParsedTradeFill? {
        guard !columnMap.isEmpty else { return nil }
        func cell(_ column: Column) -> String? {
            guard let index = columnMap[column], index < row.cells.count else { return nil }
            let value = row.cells[index].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }

        guard let symbolRaw = cell(.symbol) ?? inferSymbol(from: row.cells) else { return nil }
        let symbol = FuturesInstrumentRegistry.normalizeSymbol(symbolRaw)
        guard let quantity = CSVNumericParser.parse(cell(.quantity)) ?? 1 as Decimal?,
              let price = CSVNumericParser.parse(cell(.price))
        else { return nil }

        let action = parseAction(cell(.action) ?? cell(.side) ?? "") ?? inferAction(from: row.cells) ?? .buy
        let dateSeed = cell(.date)
        let executedAt = composeDateTime(date: dateSeed, time: cell(.time)) ?? Date()

        return ParsedTradeFill(
            id: "fill-\(row.id)",
            symbol: symbol,
            action: action,
            quantity: quantity,
            price: price,
            executedAt: executedAt,
            reportedPnL: CSVNumericParser.parse(cell(.pnl)),
            commission: CSVNumericParser.parse(cell(.commission)),
            executionID: cell(.executionID),
            orderID: cell(.orderID),
            sourcePlatform: platform,
            sourceImageIndex: row.sourceImageIndex,
            sourceRowIndex: row.id,
            warnings: executedAt == Date() ? ["Confirm date"] : []
        )
    }

    private static func parseExecutionLine(
        _ line: String,
        row: ScreenshotTableRow,
        platform: ScreenshotImportPlatform
    ) -> ParsedTradeFill? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let nsRange = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = executionRegex.firstMatch(in: trimmed, range: nsRange) else { return nil }

        func group(_ index: Int) -> String? {
            guard let range = Range(match.range(at: index), in: trimmed) else { return nil }
            return String(trimmed[range])
        }

        guard let sideRaw = group(1),
              let qtyRaw = group(2),
              let symbolRaw = group(3),
              let priceRaw = group(4),
              let quantity = CSVNumericParser.parse(qtyRaw),
              let price = CSVNumericParser.parse(priceRaw)
        else { return nil }

        let action: ParsedTradeFill.Action = sideRaw.uppercased().hasPrefix("S") ? .sell : .buy
        return ParsedTradeFill(
            id: "fill-exec-\(row.id)",
            symbol: FuturesInstrumentRegistry.normalizeSymbol(symbolRaw),
            action: action,
            quantity: quantity,
            price: price,
            executedAt: Date(),
            reportedPnL: nil,
            commission: nil,
            executionID: nil,
            orderID: nil,
            sourcePlatform: platform,
            sourceImageIndex: row.sourceImageIndex,
            sourceRowIndex: row.id,
            warnings: ["Confirm date"]
        )
    }

    private static let executionRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"^(BUY|SELL|BOT|SLD)\s+(\d+)\s+([A-Z][A-Z0-9]{1,5})\s*[@]\s*([\d,]+(?:\.\d+)?)"#,
            options: [.caseInsensitive]
        )
    }()

    private static func parseAction(_ raw: String) -> ParsedTradeFill.Action? {
        let s = raw.lowercased()
        if s.contains("buy") || s.contains("long") || s.contains("bot") { return .buy }
        if s.contains("sell") || s.contains("short") || s.contains("sld") { return .sell }
        return nil
    }

    private static func inferAction(from cells: [String]) -> ParsedTradeFill.Action? {
        parseAction(cells.joined(separator: " "))
    }

    private static func inferSymbol(from cells: [String]) -> String? {
        for cell in cells {
            let token = cell.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if token.range(of: #"^[A-Z][A-Z0-9]{0,5}$"#, options: .regularExpression) != nil,
               !["LONG", "SHORT", "BUY", "SELL"].contains(token)
            {
                return FuturesInstrumentRegistry.normalizeSymbol(token)
            }
        }
        return nil
    }

    private static func matches(_ haystack: String, any needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    private static func composeDateTime(date: String?, time: String?) -> Date? {
        if let date, let time, let combined = parseDateTime("\(date) \(time)") { return combined }
        if let date, let parsed = parseDate(date) { return parsed }
        if let time, let parsed = parseTimeToday(time) { return parsed }
        return nil
    }

    private static func parseDate(_ raw: String) -> Date? {
        let formats = ["yyyy-MM-dd", "MM/dd/yyyy", "M/d/yyyy", "MMM d, yyyy"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "America/New_York")
            formatter.dateFormat = format
            if let date = formatter.date(from: raw.trimmingCharacters(in: .whitespacesAndNewlines)) { return date }
        }
        return nil
    }

    private static func parseDateTime(_ raw: String) -> Date? {
        let formats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "MM/dd/yyyy HH:mm", "h:mm a"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "America/New_York")
            formatter.dateFormat = format
            if let date = formatter.date(from: raw.trimmingCharacters(in: .whitespacesAndNewlines)) { return date }
        }
        return parseDate(raw)
    }

    private static func parseTimeToday(_ raw: String) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        let today = calendar.startOfDay(for: Date())
        let formats = ["HH:mm:ss", "HH:mm", "h:mm a"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = format
            if let time = formatter.date(from: raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
                let parts = calendar.dateComponents([.hour, .minute, .second], from: time)
                return calendar.date(byAdding: parts, to: today)
            }
        }
        return nil
    }
}
