import Foundation

/// Stable identity for dashboard compliance recompute deduplication.
nonisolated enum TradingRulesComplianceInputFingerprint {
    static func make(
        scopeFingerprint: String,
        preferencesFingerprint: String,
        trades: [Trade],
        psychologyHistoryTrades: [Trade],
        ownerHistoryComplete: Bool,
        preferCachedInsights: Bool
    ) -> String {
        let tradeSlice = tradesContentSlice(trades)
        let psychologySlice = tradesContentSlice(psychologyHistoryTrades, label: "psych")
        return [
            scopeFingerprint,
            preferencesFingerprint,
            tradeSlice,
            psychologySlice,
            ownerHistoryComplete ? "historyComplete" : "historyPartial",
            preferCachedInsights ? "insightsCache" : "insightsRecompute",
        ].joined(separator: "|")
    }

    /// Trade-set identity, count + FNV digest of id/updatedAt so any edit invalidates stale cache.
    private static func tradesContentSlice(_ trades: [Trade], label: String = "trades") -> String {
        guard !trades.isEmpty else { return "\(label):0" }
        guard let first = trades.first, let last = trades.last else { return "\(label):0" }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for trade in trades {
            for byte in trade.id.rawValue.utf8 {
                hash ^= UInt64(byte)
                hash &*= 1_099_511_628_211
            }
            var ts = trade.updatedAt.timeIntervalSince1970.bitPattern
            withUnsafeBytes(of: &ts) { bytes in
                for byte in bytes {
                    hash ^= UInt64(byte)
                    hash &*= 1_099_511_628_211
                }
            }
        }
        return [
            "\(label):\(trades.count)",
            "fnv:\(hash)",
            first.id.rawValue,
            String(format: "%.3f", last.updatedAt.timeIntervalSince1970),
        ].joined(separator: "|")
    }
}
