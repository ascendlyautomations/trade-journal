import Foundation

/// Within-batch duplicate removal for multi-screenshot imports (Phase 1).
nonisolated enum ScreenshotTradeBatchDedup {
    static func dedupe(_ candidates: [ScreenshotParsedCandidate]) -> [ScreenshotParsedCandidate] {
        var seen = Set<String>()
        var output: [ScreenshotParsedCandidate] = []

        for candidate in candidates {
            let key = fingerprint(for: candidate)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(candidate)
        }
        return output
    }

    static func fingerprint(for candidate: ScreenshotParsedCandidate) -> String {
        if let executionID = candidate.executionID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !executionID.isEmpty
        {
            return "exec:\(executionID.lowercased())"
        }
        if let orderID = candidate.orderID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !orderID.isEmpty
        {
            return "order:\(orderID.lowercased())"
        }

        let symbol = (candidate.symbol ?? "").uppercased()
        let side = candidate.side == .short ? "S" : "L"
        let qty = decimalKey(candidate.quantity)
        let entry = decimalKey(candidate.entryPrice)
        let exit = decimalKey(candidate.exitPrice)
        let pnl = decimalKey(candidate.realizedPnL)
        let minute = minuteKey(candidate.entryAt)
        let kind = candidate.kind.rawValue
        return "\(kind)|\(symbol)|\(side)|\(qty)|\(entry)|\(exit)|\(pnl)|\(minute)"
    }

    private static func decimalKey(_ value: Decimal?) -> String {
        guard let value else { return "-" }
        return NSDecimalNumber(decimal: value).stringValue
    }

    private static func minuteKey(_ date: Date?) -> String {
        guard let date else { return "-" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
