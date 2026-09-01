import Foundation

/// Compact public account-type badge from denormalized `trades.mode` / `trades.account_type` only.
///
/// Mirrors web `publicAccountBadgeFromTrade` with native display labels (Eval, Funded, Live, …).
/// Never uses account name, account number, or private account metadata.
nonisolated enum PublicTradeAccountBadge {
    static func label(tradeMode: String?, accountType: String?) -> String? {
        if let fromMode = classifyTradingMode(tradeMode) {
            return fromMode
        }
        return classifyTradingMode(accountType)
    }

    static func label(for trade: Trade) -> String? {
        trade.publicAccountBadge
    }

    /// Maps wire `mode` / `account_type` strings to a compact public badge, or nil when unknown.
    private static func classifyTradingMode(_ raw: String?) -> String? {
        let norm = normalize(raw)
        guard !norm.isEmpty, norm != "imported" else { return nil }
        if isCategoryOnly(norm) { return nil }

        switch norm {
        case "eval", "evaluation":
            return "Eval"
        case "funded":
            return "Funded"
        case "live":
            return "Live"
        case "backtest":
            return "Backtest"
        case "sim":
            return "Sim"
        case "personal", "broker":
            return "Live"
        default:
            return nil
        }
    }

    private static func isCategoryOnly(_ norm: String) -> Bool {
        let compact = norm
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
        switch compact {
        case "propfirm", "prop":
            return true
        default:
            return false
        }
    }

    private static func normalize(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
