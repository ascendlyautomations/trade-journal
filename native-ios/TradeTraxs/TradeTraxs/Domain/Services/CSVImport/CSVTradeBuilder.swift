import Foundation

/// Native port of web `buildTradesFromParsedCsv` / format parsers.
///
/// Important web parity notes:
/// - Each CSV **data row** → one trade (no fill/execution grouping).
/// - No duplicate detection against existing journal trades.
/// - RR only when a CSV cell provides it.
nonisolated enum CSVTradeBuilder {
    private struct RowError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func detectFormat(headers: [String], firstRow: [String: String]?) -> CSVFileFormat {
        let probe = firstRow ?? Dictionary(uniqueKeysWithValues: headers.map { ($0, "1") })
        if isTradovate(probe) { return .tradovate }
        if isTradeZella(probe) { return .tradezella }
        if isEnteredExited(probe) { return .enteredExited }
        return .flexible
    }

    static func build(
        fileName: String,
        text: String,
        mappings: [CSVColumnMapping]? = nil
    ) throws -> CSVParseSummary {
        let parsed = try CSVTextParser.parse(text: text)
        let format = detectFormat(headers: parsed.headers, firstRow: parsed.rows.first)
        return build(
            fileName: fileName,
            headers: parsed.headers,
            rows: parsed.rows,
            format: format,
            mappings: mappings
        )
    }

    static func build(
        fileName: String,
        headers: [String],
        rows: [[String: String]],
        format: CSVFileFormat,
        mappings: [CSVColumnMapping]? = nil
    ) -> CSVParseSummary {
        var trades: [CSVParsedTrade] = []
        var failures: [CSVParseRowFailure] = []

        for (index, row) in rows.enumerated() {
            let rowNumber = index + 2
            let result: Result<CSVParsedTrade, RowError>
            switch format {
            case .tradovate:
                result = parseTradovate(row: row, rowNumber: rowNumber)
            case .tradezella:
                result = parseTradeZella(row: row, rowNumber: rowNumber)
            case .enteredExited:
                result = parseEnteredExited(row: row, rowNumber: rowNumber)
            case .flexible:
                let fields: [CSVLogicalField: String]
                if let mappings {
                    fields = applyMappings(row: row, mappings: mappings)
                } else {
                    fields = CSVHeaderAliases.mapHeadersToFields(row)
                }
                if fields.isEmpty {
                    result = .failure(
                        RowError(
                            message: "No recognized columns. Check headers match Date, Symbol, Direction, PnL, etc."
                        )
                    )
                } else {
                    result = parseFlexible(fields: fields, rowNumber: rowNumber)
                }
            }

            switch result {
            case .success(let trade):
                trades.append(trade)
            case .failure(let error):
                failures.append(CSVParseRowFailure(rowNumber: rowNumber, reason: error.message))
            }
        }

        return CSVParseSummary(
            format: format,
            fileName: fileName,
            totalRows: rows.count,
            successCount: trades.count,
            failedCount: failures.count,
            headers: headers,
            trades: trades,
            failures: failures
        )
    }

    static func needsManualMapping(summary: CSVParseSummary) -> Bool {
        if summary.format == .flexible,
           summary.successCount == 0,
           !summary.headers.isEmpty
        {
            return true
        }
        if summary.format == .flexible {
            let recognized = summary.headers.contains { CSVHeaderAliases.resolveField(for: $0) != nil }
            return !recognized
        }
        return false
    }

    // MARK: - Detection

    private static func isTradovate(_ row: [String: String]) -> Bool {
        for key in row.keys {
            let nk = CSVHeaderAliases.normalizeHeaderKey(key)
            if nk == "buyprice" || nk == "sellprice"
                || nk == "boughttimestamp" || nk == "soldtimestamp"
            {
                return true
            }
        }
        return false
    }

    private static func isTradeZella(_ row: [String: String]) -> Bool {
        let keys = Set(row.keys.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })
        if keys.contains("open date") && keys.contains("close date") { return true }
        if keys.contains("instrument"),
           keys.contains("p&l") || keys.contains("net p&l") || keys.contains("gross p&l")
        {
            return true
        }
        if keys.contains("avg buy price") && keys.contains("avg sell price") { return true }
        if keys.contains("open date"),
           keys.contains("p&l") || keys.contains("net p&l") || keys.contains("gross p&l")
        {
            return true
        }
        if keys.contains("reward ratio") && keys.contains("open date") { return true }
        return false
    }

    private static func isEnteredExited(_ row: [String: String]) -> Bool {
        CSVHeaderAliases.cell(in: row, aliases: CSVHeaderAliases.enteredAtAliases) != nil
            && CSVHeaderAliases.cell(in: row, aliases: CSVHeaderAliases.exitedAtAliases) != nil
    }

    // MARK: - Tradovate

    private static func parseTradovate(
        row: [String: String],
        rowNumber: Int
    ) -> Result<CSVParsedTrade, RowError> {
        let entryRaw = CSVHeaderAliases.cell(
            in: row,
            aliases: ["buyPrice", "buy price", "entry price", "entry"]
        )
        let exitRaw = CSVHeaderAliases.cell(
            in: row,
            aliases: ["sellPrice", "sell price", "exit price", "exit"]
        )
        guard entryRaw != nil, exitRaw != nil else {
            return .failure(RowError(message: "Tradovate row missing buy/sell price"))
        }
        guard let entry = CSVNumericParser.parse(entryRaw) else {
            return .failure(RowError(message: "Invalid buyPrice: \"\(entryRaw ?? "")\""))
        }
        guard let exit = CSVNumericParser.parse(exitRaw) else {
            return .failure(RowError(message: "Invalid sellPrice: \"\(exitRaw ?? "")\""))
        }
        guard let pnlRaw = CSVHeaderAliases.cell(
            in: row,
            aliases: ["pnl", "p&l", "p/l", "realized pnl", "net pnl"]
        ) else {
            return .failure(RowError(message: "Missing PnL column/value"))
        }
        guard let pnl = CSVNumericParser.parse(pnlRaw) else {
            return .failure(RowError(message: "Invalid PnL: \"\(pnlRaw)\""))
        }

        let qtyRaw = CSVHeaderAliases.cell(in: row, aliases: ["qty", "quantity", "contracts", "size"])
        var contracts: Decimal = 1
        if let qtyRaw {
            guard let qty = CSVNumericParser.parse(qtyRaw), qty > 0 else {
                return .failure(RowError(message: "Invalid qty/contracts: \"\(qtyRaw)\""))
            }
            let qtyInt = NSDecimalNumber(decimal: qty).intValue
            guard Decimal(qtyInt) == qty, qtyInt > 0 else {
                return .failure(RowError(message: "Invalid qty/contracts: \"\(qtyRaw)\""))
            }
            contracts = Decimal(qtyInt)
        }

        let symbolRaw = CSVHeaderAliases.cell(in: row, aliases: ["symbol", "ticker", "contract"]) ?? ""
        let ticker = normalizeFuturesSymbol(symbolRaw)
        let boughtTsRaw = CSVHeaderAliases.cell(
            in: row,
            aliases: ["boughtTimestamp", "bought timestamp", "entry time"]
        )
        let soldTsRaw = CSVHeaderAliases.cell(
            in: row,
            aliases: ["soldTimestamp", "sold timestamp", "exit time"]
        )
        let sideRaw = CSVHeaderAliases.cell(in: row, aliases: ["side", "direction", "action"])

        let now = Date()
        let bought = parseDate(boughtTsRaw) ?? now
        let sold = parseDate(soldTsRaw) ?? bought
        let normalized = normalizeEntryExit(
            entry: bought,
            exit: sold,
            entryPrice: entry,
            exitPrice: exit,
            swapPrices: true
        )
        let side = normalizeDirection(sideRaw)
            ?? inferSide(entry: normalized.entryPrice, exit: normalized.exitPrice)
            ?? .long

        var points: Decimal?
        if let ep = normalized.entryPrice, let xp = normalized.exitPrice {
            points = directionalPoints(side: side, entry: ep, exit: xp)
        }
        let rr = parseRR(
            CSVHeaderAliases.cell(in: row, aliases: ["rr", "r:r", "risk reward", "reward ratio"])
        )

        var warnings: [String] = []
        if ticker.isEmpty { warnings.append("Missing Symbol") }
        if boughtTsRaw == nil || soldTsRaw == nil { warnings.append("Timestamp fallback used") }

        return .success(
            makeTrade(
                rowNumber: rowNumber,
                symbol: ticker.isEmpty ? symbolRaw : ticker,
                side: side,
                quantity: max(1, contracts),
                entryPrice: normalized.entryPrice,
                exitPrice: normalized.exitPrice,
                entryAt: normalized.entry,
                exitAt: normalized.exit,
                pnl: pnl,
                rr: rr,
                points: points,
                notes: "",
                warnings: warnings
            )
        )
    }

    // MARK: - TradeZella / Entered-Exited / Flexible

    private static func parseTradeZella(
        row: [String: String],
        rowNumber: Int
    ) -> Result<CSVParsedTrade, RowError> {
        // Reuse flexible mapping after lowercasing keys to match TradeZella alias space.
        var lowered: [String: String] = [:]
        for (k, v) in row {
            lowered[k.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)] = v
        }
        func value(_ aliases: [String]) -> String? {
            for a in aliases {
                if let v = lowered[a], !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return v.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return nil
        }

        guard let pnlRaw = value(["p&l", "net p&l", "gross p&l", "pnl"]) else {
            return .failure(RowError(message: "Missing required field: PnL"))
        }
        guard let pnl = CSVNumericParser.parse(pnlRaw) else {
            return .failure(RowError(message: "Invalid PnL: \"\(pnlRaw)\""))
        }
        let symbolRaw = value(["symbol", "instrument"]) ?? ""
        let entryDate = value(["open date", "date", "trade date", "entry date"])
        let exitDate = value(["close date", "closed date", "exit date", "date"])
        guard entryDate != nil || exitDate != nil else {
            return .failure(RowError(message: "Missing required field: date"))
        }
        let entryPrice = CSVNumericParser.parse(value(["entry price", "avg buy price"]))
        let exitPrice = CSVNumericParser.parse(value(["exit price", "avg sell price"]))
        let side = normalizeDirection(value(["side"]))
            ?? inferSide(entry: entryPrice, exit: exitPrice)
            ?? .long
        let qty = CSVNumericParser.parse(value(["executions", "quantity"])) ?? 1
        let contracts = max(1, Int(truncating: qty as NSDecimalNumber))
        let baseRaw = exitDate ?? entryDate!
        guard let baseDate = parseFlexibleDate(baseRaw) else {
            return .failure(RowError(message: "Unrecognized date format: \"\(baseRaw)\""))
        }
        let entryTimeRaw = value(["open time"])
        let exitTimeRaw = value(["close time"])
        let entryAt = combineDateTimeUTC(date: entryDate ?? baseRaw, time: entryTimeRaw) ?? baseDate
        let exitAt = combineDateTimeUTC(date: exitDate ?? baseRaw, time: exitTimeRaw) ?? entryAt
        let normalized = normalizeEntryExit(
            entry: entryAt,
            exit: exitAt,
            entryPrice: entryPrice,
            exitPrice: exitPrice,
            swapPrices: false
        )
        let rr = parseRR(value(["reward ratio", "rr", "r:r"]))
        let points = CSVNumericParser.parse(value(["points"]))
        var warnings: [String] = []
        if symbolRaw.isEmpty { warnings.append("Missing Symbol") }

        return .success(
            makeTrade(
                rowNumber: rowNumber,
                symbol: normalizeFuturesSymbol(symbolRaw).isEmpty ? (symbolRaw.isEmpty ? "UNKNOWN" : symbolRaw) : normalizeFuturesSymbol(symbolRaw),
                side: side,
                quantity: Decimal(contracts),
                entryPrice: normalized.entryPrice,
                exitPrice: normalized.exitPrice,
                entryAt: normalized.entry,
                exitAt: normalized.exit,
                pnl: pnl,
                rr: rr,
                points: points,
                notes: "",
                warnings: warnings
            )
        )
    }

    private static func parseEnteredExited(
        row: [String: String],
        rowNumber: Int
    ) -> Result<CSVParsedTrade, RowError> {
        guard let enteredRaw = CSVHeaderAliases.cell(in: row, aliases: CSVHeaderAliases.enteredAtAliases),
              let exitedRaw = CSVHeaderAliases.cell(in: row, aliases: CSVHeaderAliases.exitedAtAliases)
        else {
            return .failure(RowError(message: "Missing EnteredAt / ExitedAt"))
        }
        let tradeDate = CSVHeaderAliases.mapHeadersToFields(row)[.date]
        guard let entry = parseEnteredExitedInstant(enteredRaw, tradeDate: tradeDate) else {
            return .failure(RowError(message: "Invalid entry time: \"\(enteredRaw)\""))
        }
        guard let exit = parseEnteredExitedInstant(exitedRaw, tradeDate: tradeDate) else {
            return .failure(RowError(message: "Invalid exit time: \"\(exitedRaw)\""))
        }
        let entryPrice = CSVNumericParser.parse(
            CSVHeaderAliases.cell(in: row, aliases: CSVHeaderAliases.enteredExitedEntryPrice)
        )
        let exitPrice = CSVNumericParser.parse(
            CSVHeaderAliases.cell(in: row, aliases: CSVHeaderAliases.enteredExitedExitPrice)
        )
        let pnl = CSVNumericParser.parse(
            CSVHeaderAliases.cell(in: row, aliases: CSVHeaderAliases.enteredExitedPnL)
        ) ?? 0
        let size = CSVNumericParser.parse(
            CSVHeaderAliases.cell(in: row, aliases: CSVHeaderAliases.enteredExitedSize)
        )
        let contracts = max(1, Int(truncating: (size ?? 1) as NSDecimalNumber))
        let symbolRaw = CSVHeaderAliases.cell(in: row, aliases: CSVHeaderAliases.enteredExitedSymbol) ?? ""
        let ticker = normalizeFuturesSymbol(symbolRaw)
        let normalized = normalizeEntryExit(
            entry: entry,
            exit: exit,
            entryPrice: entryPrice,
            exitPrice: exitPrice,
            swapPrices: false
        )
        let side = normalizeDirection(
            CSVHeaderAliases.cell(in: row, aliases: CSVHeaderAliases.enteredExitedDirection)
        ) ?? inferSide(entry: normalized.entryPrice, exit: normalized.exitPrice) ?? .short

        var warnings: [String] = []
        if ticker.isEmpty && symbolRaw.isEmpty { warnings.append("Missing Symbol") }
        if CSVHeaderAliases.cell(in: row, aliases: CSVHeaderAliases.enteredExitedPnL) == nil {
            warnings.append("Missing P&L (defaulted to 0)")
        }

        return .success(
            makeTrade(
                rowNumber: rowNumber,
                symbol: ticker.isEmpty ? symbolRaw : ticker,
                side: side,
                quantity: Decimal(contracts),
                entryPrice: normalized.entryPrice ?? 0,
                exitPrice: normalized.exitPrice ?? 0,
                entryAt: normalized.entry,
                exitAt: normalized.exit,
                pnl: pnl,
                rr: parseRR(CSVHeaderAliases.cell(in: row, aliases: ["rr", "r:r", "reward ratio"])),
                points: nil,
                notes: "",
                warnings: warnings
            )
        )
    }

    private static func parseFlexible(
        fields: [CSVLogicalField: String],
        rowNumber: Int
    ) -> Result<CSVParsedTrade, RowError> {
        guard let dateRaw = fields[.date], !dateRaw.isEmpty else {
            return .failure(RowError(message: "Missing required field: date"))
        }
        guard let symbolRaw = fields[.symbol], !symbolRaw.isEmpty else {
            return .failure(RowError(message: "Missing required field: symbol"))
        }
        guard let dirRaw = fields[.direction], !dirRaw.isEmpty else {
            return .failure(RowError(message: "Missing required field: direction"))
        }
        guard let pnlRaw = fields[.pnl], !pnlRaw.isEmpty else {
            return .failure(RowError(message: "Missing required field: PnL"))
        }
        guard let dateIso = parseFlexibleDate(dateRaw) else {
            return .failure(RowError(message: "Unrecognized date format: \"\(dateRaw)\""))
        }
        guard let side = normalizeDirection(dirRaw) else {
            return .failure(RowError(message: "Invalid direction: \"\(dirRaw)\""))
        }
        guard let pnl = CSVNumericParser.parse(pnlRaw) else {
            return .failure(RowError(message: "Invalid PnL: \"\(pnlRaw)\""))
        }

        let entryN = fields[.entryPrice].flatMap(CSVNumericParser.parse)
        let exitN = fields[.exitPrice].flatMap(CSVNumericParser.parse)
        if let raw = fields[.entryPrice], CSVNumericParser.parse(raw) == nil {
            return .failure(RowError(message: "Invalid entry price: \"\(raw)\""))
        }
        if let raw = fields[.exitPrice], CSVNumericParser.parse(raw) == nil {
            return .failure(RowError(message: "Invalid exit price: \"\(raw)\""))
        }

        var contracts: Decimal = 1
        if let raw = fields[.contracts] {
            guard let c = CSVNumericParser.parse(raw), c >= 0 else {
                return .failure(RowError(message: "Invalid contracts/qty: \"\(raw)\""))
            }
            contracts = c == 0 ? 1 : c
        }

        var entryAt = dateIso
        var exitAt = dateIso
        if let t = fields[.entryTime], let merged = combineLocalDateTime(date: dateIso, time: t) {
            entryAt = merged
        }
        if let t = fields[.exitTime], let merged = combineLocalDateTime(date: dateIso, time: t) {
            exitAt = merged
        }
        let normalized = normalizeEntryExit(
            entry: entryAt,
            exit: exitAt,
            entryPrice: entryN,
            exitPrice: exitN,
            swapPrices: false
        )

        var notesParts: [String] = []
        if let n = fields[.notes], !n.isEmpty { notesParts.append(sanitizeNotes(n)) }
        var costs: [String] = []
        if let c = fields[.commission].flatMap(CSVNumericParser.parse) {
            costs.append("Commission: \(c)")
        }
        if let f = fields[.fees].flatMap(CSVNumericParser.parse) {
            costs.append("Fees: \(f)")
        }
        if let s = fields[.swap].flatMap(CSVNumericParser.parse) {
            costs.append("Swap: \(s)")
        }
        if !costs.isEmpty {
            notesParts.append(costs.joined(separator: " | "))
        }

        return .success(
            makeTrade(
                rowNumber: rowNumber,
                symbol: normalizeFuturesSymbol(symbolRaw),
                side: side,
                quantity: contracts,
                entryPrice: normalized.entryPrice,
                exitPrice: normalized.exitPrice,
                entryAt: normalized.entry,
                exitAt: normalized.exit,
                pnl: pnl,
                rr: parseRR(fields[.rr]),
                points: fields[.points].flatMap(CSVNumericParser.parse),
                notes: notesParts.joined(separator: "\n"),
                warnings: [],
                strategy: fields[.strategy],
                csvAccountName: fields[.accountName],
                csvAccountID: fields[.accountID],
                csvAccountSize: fields[.accountSize],
                sessionOverride: fields[.session]
            )
        )
    }

    private static func applyMappings(
        row: [String: String],
        mappings: [CSVColumnMapping]
    ) -> [CSVLogicalField: String] {
        var out: [CSVLogicalField: String] = [:]
        for mapping in mappings {
            guard let field = mapping.field,
                  let value = row[mapping.header]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty
            else { continue }
            out[field] = value
        }
        return out
    }

    // MARK: - Shared helpers

    private static func makeTrade(
        rowNumber: Int,
        symbol: String,
        side: TradeSide,
        quantity: Decimal,
        entryPrice: Decimal?,
        exitPrice: Decimal?,
        entryAt: Date,
        exitAt: Date?,
        pnl: Decimal,
        rr: Decimal?,
        points: Decimal?,
        notes: String,
        warnings: [String],
        strategy: String? = nil,
        csvAccountName: String? = nil,
        csvAccountID: String? = nil,
        csvAccountSize: String? = nil,
        sessionOverride: String? = nil
    ) -> CSVParsedTrade {
        let status: CSVTradeParseStatus
        if symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            status = .invalid
        } else if !warnings.isEmpty {
            status = .needsReview
        } else {
            status = .ready
        }
        let session = sessionOverride?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? TradingSessionLabel.session(from: entryAt)
            ?? "NY"
        return CSVParsedTrade(
            id: "csv-row-\(rowNumber)",
            rowNumber: rowNumber,
            symbol: symbol.uppercased(),
            side: side,
            quantity: quantity,
            entryPrice: entryPrice,
            exitPrice: exitPrice,
            entryAt: entryAt,
            exitAt: exitAt,
            realizedPnL: pnl,
            riskReward: rr,
            points: points,
            sessionLabel: session,
            notes: notes,
            strategy: strategy,
            csvAccountName: csvAccountName,
            csvAccountID: csvAccountID,
            csvAccountSize: csvAccountSize,
            durationSeconds: {
                guard let exitAt else { return nil }
                let seconds = Int(exitAt.timeIntervalSince(entryAt))
                return seconds > 0 ? seconds : nil
            }(),
            status: status,
            warningMessages: warnings
        )
    }

    private static func normalizeFuturesSymbol(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !s.isEmpty else { return "" }
        // Web: /^([A-Z0-9]{1,6}?)([FGHJKMNQUVXZ])(\d{1,2})$/
        if let regex = try? NSRegularExpression(
            pattern: #"^([A-Z0-9]{1,6}?)([FGHJKMNQUVXZ])(\d{1,2})$"#
        ) {
            let range = NSRange(s.startIndex..<s.endIndex, in: s)
            if let match = regex.firstMatch(in: s, range: range),
               let root = Range(match.range(at: 1), in: s)
            {
                return String(s[root])
            }
        }
        return s
    }

    private static func normalizeDirection(_ raw: String?) -> TradeSide? {
        guard let raw else { return nil }
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty { return nil }
        if ["long", "buy", "b", "bull"].contains(s) || s.contains("long") || s.contains("buy") {
            return .long
        }
        if ["short", "sell", "s", "ss", "bear"].contains(s) || s.contains("short") || s.contains("sell") {
            return .short
        }
        return nil
    }

    private static func inferSide(entry: Decimal?, exit: Decimal?) -> TradeSide? {
        guard let entry, let exit else { return nil }
        return exit > entry ? .long : .short
    }

    private static func directionalPoints(side: TradeSide, entry: Decimal, exit: Decimal) -> Decimal {
        side == .short ? entry - exit : exit - entry
    }

    private static func parseRR(_ raw: String?) -> Decimal? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return CSVNumericParser.parse(raw)
    }

    private static func sanitizeNotes(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix("=") || s.hasPrefix("+") || s.hasPrefix("-") || s.hasPrefix("@") {
            s.removeFirst()
        }
        return s
    }

    private struct NormalizedTimes {
        var entry: Date
        var exit: Date
        var entryPrice: Decimal?
        var exitPrice: Decimal?
    }

    private static func normalizeEntryExit(
        entry: Date,
        exit: Date,
        entryPrice: Decimal?,
        exitPrice: Decimal?,
        swapPrices: Bool
    ) -> NormalizedTimes {
        if exit < entry {
            return NormalizedTimes(
                entry: exit,
                exit: entry,
                entryPrice: swapPrices ? exitPrice : entryPrice,
                exitPrice: swapPrices ? entryPrice : exitPrice
            )
        }
        return NormalizedTimes(entry: entry, exit: exit, entryPrice: entryPrice, exitPrice: exitPrice)
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: trimmed) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: trimmed) { return d }
        // Web `new Date(...)` accepts space-separated local datetimes (Entered/Exited exports).
        return DateFormatter.csvFlexible.date(from: trimmed)
            ?? DateFormatter.csvSpaceDateTime.date(from: trimmed)
            ?? DateFormatter.csvFlexibleAlt.date(from: trimmed)
    }

    private static func parseFlexibleDate(_ raw: String) -> Date? {
        if let d = parseDate(raw) { return d }
        // Date-only → noon local (web combineTradeDateAndTime)
        let datePart = raw.split(whereSeparator: { $0 == " " || $0 == "T" }).first.map(String.init) ?? raw
        for formatter in [DateFormatter.csvDateOnly, DateFormatter.csvDateOnlyAlt] {
            if let d = formatter.date(from: datePart) {
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: d)
                comps.hour = 12
                return Calendar.current.date(from: comps)
            }
        }
        return nil
    }

    private static func combineLocalDateTime(date: Date, time: String) -> Date? {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: date)
        let trimmed = time.trimmingCharacters(in: .whitespacesAndNewlines)
        if let full = parseDate(trimmed) { return full }
        let tf = DateFormatter.csvTimeOnly
        if let t = tf.date(from: trimmed) {
            let tc = cal.dateComponents([.hour, .minute, .second], from: t)
            comps.hour = tc.hour
            comps.minute = tc.minute
            comps.second = tc.second ?? 0
            return cal.date(from: comps)
        }
        return nil
    }

    private static func combineDateTimeUTC(date: String, time: String?) -> Date? {
        guard let time, !time.isEmpty else { return parseFlexibleDate(date) }
        let cleaned = time.replacingOccurrences(of: " UTC", with: "").trimmingCharacters(in: .whitespaces)
        let full = "\(date) \(cleaned) UTC"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        if let d = formatter.date(from: full) { return d }
        formatter.dateFormat = "yyyy-MM-dd h:mm:ss a 'UTC'"
        if let d = formatter.date(from: full) { return d }
        formatter.dateFormat = "M/d/yyyy h:mm:ss a 'UTC'"
        if let d = formatter.date(from: full) { return d }
        return parseFlexibleDate(date)
    }

    private static func parseEnteredExitedInstant(_ raw: String, tradeDate: String?) -> Date? {
        if let d = parseDate(raw) { return d }
        guard let tradeDate, let base = parseFlexibleDate(tradeDate) else { return nil }
        return combineLocalDateTime(date: base, time: raw)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

private extension DateFormatter {
    static let csvFlexible: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return f
    }()

    /// Matches JS Date parsing for `2026-02-01 09:30:00` style EnteredAt/ExitedAt cells.
    static let csvSpaceDateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static let csvFlexibleAlt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "M/d/yyyy h:mm:ss a"
        return f
    }()

    static let csvDateOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let csvDateOnlyAlt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "M/d/yyyy"
        return f
    }()

    static let csvTimeOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h:mm:ss a"
        return f
    }()
}
