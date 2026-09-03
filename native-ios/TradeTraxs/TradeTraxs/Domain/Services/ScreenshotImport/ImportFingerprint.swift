import CryptoKit
import Foundation

/// Deterministic, versioned import fingerprints — no sensitive screenshot content.
nonisolated enum ImportFingerprint {
    static let version = "v1"

    static func forAggregatedTrade(
        symbol: String,
        side: TradeSide,
        quantity: Decimal,
        entryPrice: Decimal?,
        exitPrice: Decimal?,
        entryAt: Date,
        exitAt: Date?,
        accountID: String?,
        executionIDs: [String] = [],
        orderIDs: [String] = []
    ) -> String {
        if !executionIDs.isEmpty {
            let joined = executionIDs.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .sorted()
                .joined(separator: "|")
            if !joined.isEmpty {
                return hash("exec:\(joined)")
            }
        }
        if !orderIDs.isEmpty {
            let joined = orderIDs.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .sorted()
                .joined(separator: "|")
            if !joined.isEmpty {
                return hash("order:\(joined)")
            }
        }

        let payload = [
            version,
            FuturesInstrumentRegistry.normalizeSymbol(symbol),
            side == .long ? "L" : "S",
            decimalKey(quantity),
            decimalKey(entryPrice),
            decimalKey(exitPrice),
            minuteKey(entryAt),
            minuteKey(exitAt),
            accountID ?? "-",
        ].joined(separator: "|")
        return hash(payload)
    }

    static func forFill(_ fill: ParsedTradeFill) -> String {
        if let executionID = fill.executionID?.trimmingCharacters(in: .whitespacesAndNewlines), !executionID.isEmpty {
            return hash("fill-exec:\(executionID.lowercased())")
        }
        if let orderID = fill.orderID?.trimmingCharacters(in: .whitespacesAndNewlines), !orderID.isEmpty {
            return hash("fill-order:\(orderID.lowercased())")
        }
        let payload = [
            version,
            FuturesInstrumentRegistry.normalizeSymbol(fill.symbol),
            fill.action.rawValue,
            decimalKey(fill.quantity),
            decimalKey(fill.price),
            minuteKey(fill.executedAt),
        ].joined(separator: "|")
        return hash(payload)
    }

    private static func hash(_ payload: String) -> String {
        let digest = SHA256.hash(data: Data(payload.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(version):\(hex)"
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
