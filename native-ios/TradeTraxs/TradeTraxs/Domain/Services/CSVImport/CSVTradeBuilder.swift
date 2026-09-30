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
        let probe = firstRow ?? Dictionary(headers.map { ($0, "1") }, uniquingKeysWith: { _, last in last })
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
        print("[CSV] headers parsed")
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
        format: CSVFileFormat? = nil,
        mappings: [CSVColumnMapping]? = nil
    ) -> CSVParseSummary {
        var trades: [CSVParsedTrade] = []
        var failures: [CSVParseRowFailure] = []

        let isTradovateFile = rows.first.map { isTradovate($0) } ?? false
        let summaryFormat = format ?? detectFormat(headers: headers, firstRow: rows.first)

        for (index, row) in rows.enumerated() {
            let rowNumber = index + 2
            let result = parseRow(
                row: row,
                rowNumber: rowNumber,
                isTradovateFile: isTradovateFile,
                mappings: mappings
            )

            switch result {
            case .success(let trade):
                trades.append(trade)
            case .failure(let error):
                failures.append(CSVParseRowFailure(rowNumber: rowNumber, reason: error.message))
            }
        }

        #if DEBUG
        print("[CSV] detected format=\(summaryFormat.rawValue)")
        print(
            "[CSV] normalized headers=\(headers.map { CSVHeaderAliases.normalizeHeaderKey($0) }.joined(separator: " | "))"
        )
        print(
            "[CSV] total CSV rows=\(rows.count) candidate rows=\(rows.count) parsed rows=\(trades.count) rejected rows=\(failures.count) final trade count=\(trades.count)"
        )
        for failure in failures {
            print("[CSV] rejected row=\(failure.rowNumber) reason=\(redactedRejectionReason(failure.reason))")
        }
        #endif
        print("[CSV] rows parsed")
        return CSVParseSummary(
            format: summaryFormat,
            fileName: fileName,
            totalRows: rows.count,
            successCount: trades.count,
            failedCount: failures.count,
            headers: headers,
            trades: trades,
            failures: failures
        )
    }

    /// Web `buildTradesFromParsedCsv` row dispatch.
    private static func parseRow(
        row: [String: String],
        rowNumber: Int,
        isTradovateFile: Bool,
        mappings: [CSVColumnMapping]?
    ) -> Result<CSVParsedTrade, RowError> {
        if isTradovateFile {
            return parseTradovate(row: row, rowNumber: rowNumber)
        }
        if let mappings {
            let fields = applyMappings(row: row, mappings: mappings)
            if fields.isEmpty {
                return .failure(
                    RowError(
                        message: "No recognized columns. Check headers match Date, Symbol, Direction, PnL, etc."
                    )
                )
            }
            return parseFlexible(fields: fields, rowNumber: rowNumber)
        }
        let zellaNorm = normalizeRowKeysForTradeZella(row)
        if isTradeZellaShaped(zellaNorm) {
            return parseTradeZella(row: row, rowNumber: rowNumber)
        }
        if isEnteredExited(row) {
            return parseEnteredExited(row: row, rowNumber: rowNumber)
        }
        let fields = CSVHeaderAliases.mapHeadersToFields(row)
        if fields.isEmpty {
            return .failure(
                RowError(
                    message: "No recognized columns. Check headers match Date, Symbol, Direction, PnL, etc."
                )
            )
        }
        return parseFlexible(fields: fields, rowNumber: rowNumber)
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

    private static func normalizeRowKeysForTradeZella(_ row: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in row {
            let k = key.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if !k.isEmpty { out[k] = value }
        }
        return out
    }

    /// Web `isTradeZellaShapedRow` — header keys only.
    private static func isTradeZellaShaped(_ normalized: [String: String]) -> Bool {
        let keys = Set(normalized.keys)
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

    private static func isTradeZella(_ row: [String: String]) -> Bool {
        isTradeZellaShaped(normalizeRowKeysForTradeZella(row))
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
        if entryRaw == nil || exitRaw == nil {
            return .failure(RowError(message: "Tradovate row missing buy/sell price"))
        }
        let entry = CSVNumericParser.parse(entryRaw)
        let exit = CSVNumericParser.parse(exitRaw)
        if entryRaw != nil, entry == nil {
            return .failure(RowError(message: "Invalid buyPrice: \"\(entryRaw ?? "")\""))
        }
        if exitRaw != nil, exit == nil {
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
        let durationRaw = CSVHeaderAliases.cell(
            in: row,
            aliases: ["duration", "trade duration", "hold time", "time in trade", "hold"]
        )

        let boughtOpt = resolveTradovateTimestamp(raw: boughtTsRaw)
        let soldOpt = resolveTradovateTimestamp(raw: soldTsRaw)
        let now = Date()
        let bought = boughtOpt ?? now
        let sold = soldOpt ?? bought
        let normalized = CSVEntryExitNormalization.normalize(
            entry: bought,
            exit: sold,
            entryPrice: entry,
            exitPrice: exit,
            swapPricesWhenReordering: true
        )
        let side = normalizeDirection(sideRaw)
            ?? inferSide(entry: normalized.entryPrice, exit: normalized.exitPrice)
            ?? .long

        var points: Decimal?
        if let ep = normalized.entryPrice, let xp = normalized.exitPrice {
            var computed = directionalPoints(side: side, entry: ep, exit: xp)
            let tickSizeRaw = CSVHeaderAliases.cell(
                in: row,
                aliases: ["_tickSize", "tickSize", "tick size"]
            )
            if let tickSizeRaw, let tickSize = CSVNumericParser.parseDouble(tickSizeRaw), tickSize > 0 {
                computed = Decimal(roundPointsToTickSize(
                    NSDecimalNumber(decimal: computed).doubleValue,
                    tickSize: tickSize
                ))
            }
            points = computed
        }
        let rr = parseRR(CSVHeaderAliases.rrCell(in: row))

        var durationSeconds = normalized.durationSeconds
        if durationSeconds == nil, let durationRaw {
            durationSeconds = CSVDurationParsing.parse(durationRaw)
        }

        var warnings: [String] = []
        if ticker.isEmpty { warnings.append("Missing Symbol") }
        if boughtOpt == nil || soldOpt == nil { warnings.append("Timestamp fallback used") }

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
                warnings: warnings,
                durationSeconds: durationSeconds
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
        guard let baseRaw = exitDate ?? entryDate else {
            return .failure(RowError(message: "Missing required field: date"))
        }
        guard let baseDate = parseFlexibleDate(baseRaw) else {
            return .failure(RowError(message: "Unrecognized date format: \"\(baseRaw)\""))
        }
        let entryTimeRaw = value(["open time"])
        let exitTimeRaw = value(["close time"])
        let entryAt = combineDateTimeUTC(date: entryDate ?? baseRaw, time: entryTimeRaw) ?? baseDate
        let exitAt = combineDateTimeUTC(date: exitDate ?? baseRaw, time: exitTimeRaw) ?? entryAt
        let now = Date()
        let entryResolved = entryAt.timeIntervalSince1970.isFinite ? entryAt : now
        let exitResolved = exitAt.timeIntervalSince1970.isFinite ? exitAt : entryResolved
        let normalized = CSVEntryExitNormalization.normalize(
            entry: entryResolved,
            exit: exitResolved,
            entryPrice: entryPrice,
            exitPrice: exitPrice,
            swapPricesWhenReordering: false
        )
        let rr = parseRR(CSVHeaderAliases.rrCell(in: row))
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
                warnings: warnings,
                durationSeconds: normalized.durationSeconds
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
        #if DEBUG
        if exit <= entry {
            print(
                """
                [CSV_TIME_TRACE]
                date=\(tradeDate ?? "")
                rawEntry=\(enteredRaw)
                rawExit=\(exitedRaw)
                combinedEntry=\(entry)
                combinedExitBeforeNormalization=\(exit)
                """
            )
        }
        #endif
        let normalized = CSVEntryExitNormalization.normalize(
            entry: entry,
            exit: exit,
            entryPrice: entryPrice,
            exitPrice: exitPrice,
            swapPricesWhenReordering: false
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
                rr: parseRR(CSVHeaderAliases.rrCell(in: row)),
                points: nil,
                notes: "",
                warnings: warnings,
                durationSeconds: normalized.durationSeconds
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
            let cInt = NSDecimalNumber(decimal: c).intValue
            guard Decimal(cInt) == c else {
                return .failure(RowError(message: "Invalid contracts/qty: \"\(raw)\""))
            }
            contracts = c == 0 ? 1 : Decimal(max(0, cInt))
        }

        var entryAt = dateIso
        var exitAt = dateIso
        if let t = fields[.entryTime], let merged = combineLocalDateTime(date: dateIso, time: t) {
            entryAt = merged
        }
        if let t = fields[.exitTime], let merged = combineLocalDateTime(date: dateIso, time: t) {
            exitAt = merged
        }
        let normalized = CSVEntryExitNormalization.normalize(
            entry: entryAt,
            exit: exitAt,
            entryPrice: entryN,
            exitPrice: exitN,
            swapPricesWhenReordering: false
        )

        var durationSeconds = normalized.durationSeconds
        if durationSeconds == nil, let durationText = fields[.duration] {
            durationSeconds = CSVDurationParsing.parse(durationText)
        }

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
                sessionOverride: fields[.session],
                durationSeconds: durationSeconds
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
        sessionOverride: String? = nil,
        durationSeconds explicitDuration: Int? = nil
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
            durationSeconds: explicitDuration ?? {
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

    #if DEBUG
    /// Keeps the failure category and drops the quoted cell so logs stay free of trade values.
    private static func redactedRejectionReason(_ reason: String) -> String {
        guard let quote = reason.firstIndex(of: "\"") else { return reason }
        return String(reason[..<quote]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    #endif

    private static func sanitizeNotes(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix("=") || s.hasPrefix("+") || s.hasPrefix("-") || s.hasPrefix("@") {
            s.removeFirst()
        }
        return s
    }

    /// Web Tradovate: missing/blank/unparseable → nil (caller falls back to `now`).
    private static func resolveTradovateTimestamp(raw: String?) -> Date? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return parseDate(trimmed)
    }

    /// Web `roundPointsToTickSize`.
    private static func roundPointsToTickSize(_ points: Double, tickSize: Double) -> Double {
        guard tickSize.isFinite, tickSize > 0 else { return points }
        let tickString = String(tickSize)
        let decimals: Int = {
            guard let dot = tickString.firstIndex(of: ".") else { return 0 }
            return tickString.distance(from: tickString.index(after: dot), to: tickString.endIndex)
        }()
        let snapped = (points / tickSize).rounded() * tickSize
        let precision = min(decimals + 2, 8)
        let factor = pow(10.0, Double(precision))
        return (snapped * factor).rounded() / factor
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: trimmed) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: trimmed) { return d }
        // Web `new Date(...)` accepts space-separated local datetimes (Entered/Exited + Tradovate Performance).
        return DateFormatter.csvFlexible.date(from: trimmed)
            ?? DateFormatter.csvSpaceDateTime.date(from: trimmed)
            ?? DateFormatter.csvTradovate24hDateTime.date(from: trimmed)
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
        CSVTimeParsing.combineLocalDate(date, timeRaw: time, parseFullDateTime: parseDate)
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

private nonisolated extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

private nonisolated extension DateFormatter {
    nonisolated static let csvFlexible: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return f
    }()

    /// Matches JS Date parsing for `2026-02-01 09:30:00` style EnteredAt/ExitedAt cells.
    nonisolated static let csvSpaceDateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    /// Tradovate Performance CSV — `05/05/2026 20:11:36` (24-hour local).
    nonisolated static let csvTradovate24hDateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "M/d/yyyy HH:mm:ss"
        return f
    }()

    nonisolated static let csvFlexibleAlt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "M/d/yyyy h:mm:ss a"
        return f
    }()

    nonisolated static let csvDateOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    nonisolated static let csvDateOnlyAlt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "M/d/yyyy"
        return f
    }()

}
