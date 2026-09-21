import Foundation

/// Server-aligned analytical bucket helpers (ET civil day, mode_effective).
nonisolated enum AnalyticsTradeAnalyticalScope {
    static func calendarDay(for trade: Trade) -> String? {
        AnalyticsCalendarDay.key(for: trade)
    }

    static func accountID(for trade: Trade) -> String? {
        trade.accountID?.rawValue
    }

    static func modeEffective(for trade: Trade) -> String {
        if let accountMode = trade.accountMode {
            return modeEffective(accountMode: accountMode, tradeMode: trade.mode)
        }
        return modeEffective(accountMode: nil, tradeMode: trade.mode)
    }

    static func modeEffective(accountMode: TradingAccountMode?, tradeMode: TradeMode) -> String {
        let raw: String? = {
            if let accountMode {
                return accountMode.rawValue
            }
            switch tradeMode {
            case .live: return "live"
            case .sim, .replay: return "sim"
            case .backtest: return "backtest"
            case .copyTraded: return "live"
            }
        }()
        return normalizeMode(raw)
    }

    static func normalizeMode(_ raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        switch trimmed {
        case "eval", "evaluation":
            return "evaluation"
        case "funded":
            return "funded"
        case "sim", "replay":
            return "sim"
        case "backtest":
            return "backtest"
        case "live":
            return "live"
        default:
            return trimmed.isEmpty ? "unknown" : trimmed
        }
    }

    static func boundedCalendarRange(oldDay: String?, newDay: String?) -> (start: String, end: String)? {
        let days = [oldDay, newDay].compactMap { $0 }
        guard let start = days.min(), let end = days.max() else { return nil }
        return (start, end)
    }

    static func allAccountsAllModesRange(
        viewerID: ProfileID,
        oldDay: String?,
        newDay: String?
    ) -> AnalyticsCalendarRangeIntent? {
        guard let bounds = boundedCalendarRange(oldDay: oldDay, newDay: newDay) else { return nil }
        return AnalyticsCalendarRangeIntent(
            viewerID: viewerID,
            startDate: bounds.start,
            endDate: bounds.end,
            accountScope: AnalyticsScopeKeys.allAccountsQuery,
            modeScope: AnalyticsScopeKeys.allModesQuery,
            targetRevision: nil
        )
    }
}
