import Foundation

nonisolated enum TradingRuleTemplateID: String, CaseIterable, Identifiable, Sendable {
    case scalper
    case dayTrader = "day_trader"
    case propFirm = "prop_firm"
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .scalper: return "Scalper"
        case .dayTrader: return "Day Trader"
        case .propFirm: return "Prop Firm Trader"
        case .custom: return "Custom"
        }
    }

    var detail: String {
        switch self {
        case .scalper:
            return "Higher trade count, short holds, core NY liquidity windows."
        case .dayTrader:
            return "Session-based entries with a modest daily cap and weekday focus."
        case .propFirm:
            return "Daily/weekly loss limits, profit stop, and per-trade risk caps."
        case .custom:
            return "Keep your current draft — no suggested values."
        }
    }
}

nonisolated enum TradingRuleTemplates {
    static func suggestedGlobal(for template: TradingRuleTemplateID) -> TradingPreferenceGlobal? {
        guard template != .custom else { return nil }
        var base = TradingPreferenceGlobal.empty(userID: ProfileID("template"))
        switch template {
        case .scalper:
            base.tradingStyle = .scalper
            base.preferredSessions = ["NY AM", "NY Lunch"]
            base.maxTradesPerDay = 25
            base.minAcceptableRr = 1.5
            base.maxContractsPerTrade = 4
            base.allowedTradingDays = ["monday", "tuesday", "wednesday", "thursday", "friday"]
            base.plannedStartMinute = 9 * 60 + 30
            base.plannedEndMinute = 12 * 60
        case .dayTrader:
            base.tradingStyle = .dayTrader
            base.preferredSessions = ["NY AM", "NY PM"]
            base.maxTradesPerDay = 8
            base.targetRr = 2
            base.minAcceptableRr = 1.5
            base.allowedTradingDays = ["monday", "tuesday", "wednesday", "thursday", "friday"]
            base.plannedStartMinute = 9 * 60 + 30
            base.plannedEndMinute = 16 * 60
        case .propFirm:
            base.maxTradesPerDay = 6
            base.dailyLossLimit = 500
            base.dailyProfitTarget = 500
            base.stopAfterDailyProfitTarget = true
            base.maxWeeklyLoss = 1500
            base.maxRiskPerTrade = 150
            base.maxContractsPerTrade = 10
            base.allowedTradingDays = ["monday", "tuesday", "wednesday", "thursday", "friday"]
        case .custom:
            return nil
        }
        return base
    }
}
