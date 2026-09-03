import Foundation

/// Normalized column keys for broker screenshot tables.
nonisolated enum ScreenshotColumnKey: String, Hashable, Codable, Sendable, CaseIterable {
    case symbol
    case side
    case volume
    case openPrice
    case closePrice
    case openTime
    case closeTime
    case tradeDay
    case pnl
    case fees
    case openSide
    case closeSide
    case tradeID
    case orderID
    case executionID
    case orderType
    case status
    case action
    case price
    case filledQuantity
    case timestamp
    case position
    case accountID
    case username
    case tradeDuration
    case chart
    case commission
}

/// Maps OCR header text (including common misreads) to column keys.
nonisolated enum ScreenshotColumnHeaderCatalog {
    static func classifyHeader(_ raw: String) -> ScreenshotColumnKey? {
        let s = normalizeHeader(raw)
        if s.isEmpty { return nil }

        if matches(s, any: ["account id", "account #", "account no", "acct"]) { return .accountID }
        if matches(s, any: ["username", "user name", "user", "email"]) { return .username }
        if matches(s, any: ["trade duration", "duration", "hold time"]) { return .tradeDuration }
        if matches(s, any: ["chart", "graph"]) { return .chart }
        if s == "commission" || s == "comm" { return .commission }

        if matches(s, any: ["open time", "entry time", "time in", "opened"]) { return .openTime }
        if matches(s, any: ["close time", "exit time", "time out", "closed"]) { return .closeTime }
        if matches(s, any: ["trade day", "trade date", "day"]) && !s.contains("duration") { return .tradeDay }
        if matches(s, any: ["timestamp", "executed", "execution time", "time"]) &&
            !s.contains("open") && !s.contains("close") && !s.contains("duration")
        {
            return .timestamp
        }

        if matches(s, any: ["symbol", "sym", "ticker", "instrument", "contract", "product"]) { return .symbol }
        if isSideHeader(s) { return .side }
        if matches(s, any: ["position", "pos"]) { return .position }
        if matches(s, any: ["open side", "entry side"]) { return .openSide }
        if matches(s, any: ["close side", "exit side"]) { return .closeSide }

        if matches(s, any: ["volume", "vol", "qty", "quantity", "contracts", "size"]) &&
            !s.contains("filled")
        {
            return .volume
        }
        if matches(s, any: ["filled qty", "fill qty", "fill quantity"]) ||
            (s.contains("filled") && (s.contains("qty") || s.contains("quantity")))
        {
            return .filledQuantity
        }

        if matches(s, any: ["open price", "entry price", "avg entry", "buy price"]) { return .openPrice }
        if matches(s, any: ["close price", "exit price", "avg exit", "sell price"]) { return .closePrice }
        if s == "entry" { return .openPrice }
        if s == "exit" { return .closePrice }
        if matches(s, any: ["price", "fill price", "execution price", "avg price"]) &&
            !s.contains("open") && !s.contains("close")
        {
            return .price
        }

        if isPnLHeader(s) { return .pnl }
        if matches(s, any: ["fees and commissions", "fees", "commission", "comm"]) &&
            !s.contains("position")
        {
            return .fees
        }

        if matches(s, any: ["trade id", "trade #", "trade no"]) || s.contains("trade") && s.contains("id") {
            return .tradeID
        }
        if matches(s, any: ["order id", "order #", "order no"]) { return .orderID }
        if matches(s, any: ["exec id", "execution id", "fill id"]) { return .executionID }

        if matches(s, any: ["order type", "ord type"]) { return .orderType }
        if matches(s, any: ["status", "state"]) { return .status }
        if matches(s, any: ["action", "trigger", "description", "notes"]) { return .action }

        return nil
    }

    static func normalizeHeader(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isSideHeader(_ s: String) -> Bool {
        if matches(s, any: ["side", "direction", "b/s", "buy/sell"]) { return true }
        // Common OCR misreads for SIDE
        if s == "sine" || s == "sde" || s.hasPrefix("sid") { return true }
        return false
    }

    private static func isPnLHeader(_ s: String) -> Bool {
        if matches(s, any: ["p&l", "pnl", "p/l", "profit", "net p&l", "realized", "net"]) &&
            !s.contains("open")
        {
            return true
        }
        // OCR: PAL, PNL truncated
        if s == "pal" || s == "pl" || s == "pn" { return true }
        return false
    }

    private static func matches(_ haystack: String, any needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }
}
