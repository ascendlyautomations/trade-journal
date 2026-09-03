import Foundation

/// Authoritative local futures instrument metadata — no network calls.
nonisolated enum FuturesInstrumentRegistry {
    nonisolated struct Spec: Hashable, Sendable {
        var canonicalSymbol: String
        var tickSize: Decimal
        var tickValue: Decimal
        var pointValue: Decimal
    }

    private static let specs: [String: Spec] = [
        "MNQ": Spec(canonicalSymbol: "MNQ", tickSize: 0.25, tickValue: 0.50, pointValue: 2),
        "NQ": Spec(canonicalSymbol: "NQ", tickSize: 0.25, tickValue: 5, pointValue: 20),
        "MES": Spec(canonicalSymbol: "MES", tickSize: 0.25, tickValue: 1.25, pointValue: 5),
        "ES": Spec(canonicalSymbol: "ES", tickSize: 0.25, tickValue: 12.50, pointValue: 50),
        "MCL": Spec(canonicalSymbol: "MCL", tickSize: 0.01, tickValue: 1, pointValue: 100),
        "CL": Spec(canonicalSymbol: "CL", tickSize: 0.01, tickValue: 10, pointValue: 1000),
        "MGC": Spec(canonicalSymbol: "MGC", tickSize: 0.10, tickValue: 1, pointValue: 10),
        "GC": Spec(canonicalSymbol: "GC", tickSize: 0.10, tickValue: 10, pointValue: 100),
        "MYM": Spec(canonicalSymbol: "MYM", tickSize: 1, tickValue: 0.50, pointValue: 0.50),
        "YM": Spec(canonicalSymbol: "YM", tickSize: 1, tickValue: 5, pointValue: 5),
    ]

    static func resolve(symbol raw: String) -> Spec? {
        let normalized = normalizeSymbol(raw)
        guard !normalized.isEmpty else { return nil }
        return specs[normalized]
    }

    static func normalizeSymbol(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.isEmpty { return s }

        let brokerPattern = #"(?:XCME[_\s.\-]*\w+\s+)?([A-Z]{2,4})\s*\([A-Z]?\d{1,2}\)"#
        if let regex = try? NSRegularExpression(pattern: brokerPattern),
           let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
           let root = Range(match.range(at: 1), in: s)
        {
            let code = String(s[root])
            if specs[code] != nil { return code }
        }

        for key in specs.keys.sorted(by: { $0.count > $1.count }) {
            if s.contains(key) { return key }
        }

        let pattern = #"^([A-Z0-9]{1,6}?)([FGHJKMNQUVXZ])(\d{1,2})$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
           let root = Range(match.range(at: 1), in: s)
        {
            return String(s[root])
        }
        return s
    }

    static func grossPnL(
        spec: Spec,
        side: TradeSide,
        entryPrice: Decimal,
        exitPrice: Decimal,
        quantity: Decimal
    ) -> Decimal {
        let points = directionalPoints(side: side, entry: entryPrice, exit: exitPrice)
        return points * spec.pointValue * quantity
    }

    static func directionalPoints(side: TradeSide, entry: Decimal, exit: Decimal) -> Decimal {
        side == .short ? entry - exit : exit - entry
    }
}
