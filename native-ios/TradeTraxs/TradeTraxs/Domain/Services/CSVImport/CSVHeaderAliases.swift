import Foundation

/// Web `HEADER_ALIAS_TO_FIELD` / `normalizeHeaderKey` / Tradovate & Entered-Exited aliases.
nonisolated enum CSVHeaderAliases {
    static func normalizeHeaderKey(_ header: String) -> String {
        var s = header.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.first == "\u{FEFF}" { s.removeFirst() }
        s = s.lowercased()
        s = s.replacingOccurrences(of: #"[\u{200B}-\u{200D}\u{FEFF}]"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[_\\-]+"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[^a-z0-9\s]"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func resolveField(for header: String) -> CSVLogicalField? {
        aliasMap[normalizeHeaderKey(header)]
    }

    static func mapHeadersToFields(_ row: [String: String]) -> [CSVLogicalField: String] {
        var out: [CSVLogicalField: String] = [:]
        for (rawKey, val) in row {
            guard let field = resolveField(for: rawKey) else { continue }
            let s = val.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { out[field] = s }
        }
        return out
    }

    static func cell(in row: [String: String], aliases: [String]) -> String? {
        let normalizedToRaw = Dictionary(
            uniqueKeysWithValues: row.keys.map { (normalizeHeaderKey($0), $0) }
        )
        for alias in aliases {
            guard let rawKey = normalizedToRaw[normalizeHeaderKey(alias)],
                  let value = row[rawKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty
            else { continue }
            return value
        }
        return nil
    }

    static func suggestedMappings(for headers: [String]) -> [CSVColumnMapping] {
        headers.map { header in
            CSVColumnMapping(header: header, field: resolveField(for: header))
        }
    }

    // MARK: - Alias tables (web `buildHeaderAliasMap`)

    private static let aliasMap: [String: CSVLogicalField] = {
        var map: [String: CSVLogicalField] = [:]
        let groups: [CSVLogicalField: [String]] = [
            .date: [
                "date", "trade date", "entry date", "exit date", "close date", "closed date",
                "open date", "exec date", "execution date", "timestamp", "fill time",
                "execution time", "order time",
            ],
            .symbol: [
                "symbol", "ticker", "instrument", "contract", "underlying", "product",
                "market", "security", "asset",
            ],
            .direction: [
                "direction", "side", "buy sell", "position", "action", "type", "long short",
                "order side", "trade type", "order action", "position type",
            ],
            .entryPrice: [
                "entry price", "entry", "avg entry", "open price", "entry px",
                "avg entry price", "avg buy price", "buy price",
            ],
            .exitPrice: [
                "exit price", "exit", "avg exit", "close price", "avg exit price",
                "avg sell price", "sell price",
            ],
            .pnl: [
                "pnl", "p l", "p  l", "profit", "net profit", "realized pnl", "realized p l",
                "realized profit", "net pnl", "net p l", "gross pnl", "gross p l",
                "gross profit", "trade pnl", "result", "net result", "gain", "gain loss",
                "profitusd", "net", "pl",
            ],
            .contracts: [
                "contracts", "contract size", "executions", "qty", "quantity", "size",
                "volume", "lots", "shares", "units", "position size",
            ],
            .points: ["points", "net points", "tick gain", "ticks"],
            .rr: [
                "rr", "r r", "risk reward", "risk reward ratio", "reward risk",
                "r multiple", "r multiple ratio", "r", "reward ratio", "realized rr", "riskreward",
            ],
            .session: ["session", "market session", "trading session"],
            .accountName: [
                "account", "account name", "firm", "broker", "prop firm", "prop account",
                "funded account", "workspace", "login",
            ],
            .accountID: ["account id", "acct id", "account number", "acct", "account #"],
            .accountSize: ["account size", "eval size", "funded size", "acct size"],
            .strategy: ["strategy", "setup", "playbook", "system"],
            .commission: [
                "commission", "commissions", "comm", "broker commission", "transaction cost",
            ],
            .fees: [
                "fees", "fee", "exchange fee", "exchange fees", "broker fees", "platform fee",
            ],
            .swap: ["swap", "swap fee", "overnight fee", "financing"],
            .notes: ["notes", "comment", "description", "remarks"],
            .entryTime: [
                "entry time", "entrytime", "entered at", "enteredat", "entered at",
                "open time", "open datetime", "opendatetime", "start time", "time in",
                "entry timestamp", "in time",
            ],
            .exitTime: [
                "exit time", "exittime", "exited at", "exitedat", "exited at",
                "close time", "close datetime", "closedatetime", "end time", "time out",
                "exit timestamp", "out time",
            ],
            .duration: ["duration", "trade duration", "hold time", "time in trade", "hold"],
        ]
        for (field, aliases) in groups {
            for alias in aliases {
                let key = normalizeHeaderKey(alias)
                if map[key] == nil { map[key] = field }
            }
        }
        return map
    }()

    static let enteredAtAliases = [
        "EnteredAt", "entered at", "entered_at", "entry time", "EntryTime", "entrytime",
        "open time", "Open Time", "OpenDateTime", "open datetime", "start time", "Start Time",
    ]

    static let exitedAtAliases = [
        "ExitedAt", "exited at", "exited_at", "exit time", "ExitTime", "exittime",
        "close time", "Close Time", "CloseDateTime", "close datetime", "end time", "End Time",
    ]

    static let enteredExitedEntryPrice = [
        "EntryPrice", "entry price", "entry", "avg entry", "open price",
    ]
    static let enteredExitedExitPrice = [
        "ExitPrice", "exit price", "exit", "avg exit", "close price",
    ]
    static let enteredExitedPnL = [
        "PnL", "pnl", "p&l", "net pnl", "profit", "realized pnl",
    ]
    static let enteredExitedSize = [
        "Qty", "qty", "quantity", "contracts", "size", "Quantity",
    ]
    static let enteredExitedSymbol = [
        "Symbol", "symbol", "ticker", "instrument", "contract", "ContractName",
    ]
    static let enteredExitedDirection = [
        "Side", "side", "direction", "action", "type", "Type",
    ]
}
