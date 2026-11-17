import Foundation

/// Optional trading-analytics preferences. Mirrors `lib/analytics/tradingPreferences.ts`.
/// A nil field means that rule is off. Do not assume a style or a starter cap.
nonisolated enum TradingStyleID: String, Codable, CaseIterable, Sendable {
    case scalper
    case dayTrader = "day_trader"
    case swingTrader = "swing_trader"

    var label: String {
        switch self {
        case .scalper: return "Scalper"
        case .dayTrader: return "Day Trader"
        case .swingTrader: return "Swing Trader"
        }
    }

    var detail: String {
        switch self {
        case .scalper: return "Many short trades inside a session."
        case .dayTrader: return "Trades opened and closed on the same day."
        case .swingTrader: return "Trades held beyond the session."
        }
    }
}

nonisolated struct TradingPreferenceGlobal: Equatable, Sendable {
    var userID: ProfileID
    var tradingStyle: TradingStyleID?
    var preferredSessions: [String]
    var primaryInstruments: [String]
    var targetRr: Double?
    var maxTradesPerDay: Int?
    var dailyLossLimit: Double?
    var consecutiveLossPause: Int?
    var breakevenTolerance: Double?
    var dailyProfitTarget: Double?
    var maxDrawdownGoal: Double?
    var plannedStartMinute: Int?
    var plannedEndMinute: Int?
    var waitAfterLossMinutes: Int?
    var maxRiskPerTrade: Double?
    var minAcceptableRr: Double?
    var allowedTradingDays: [String]
    var maxContractsPerTrade: Int?
    var maxWeeklyLoss: Double?
    var stopAfterDailyProfitTarget: Bool
    var maxTradesPerDayScope: TradingRuleScope
    var dailyLossLimitScope: TradingRuleScope
    var dailyProfitRulesScope: TradingRuleScope
    var maxWeeklyLossScope: TradingRuleScope
    /// When true, trades before the first saved rule revision use the current global rules.
    var applyRulesToPastTrades: Bool
    /// Personal compliance goal for analytics (0–100). Does not affect checks.
    var personalComplianceTargetPercent: Double?
    var updatedAt: Date?

    static func empty(userID: ProfileID) -> TradingPreferenceGlobal {
        TradingPreferenceGlobal(
            userID: userID,
            tradingStyle: nil,
            preferredSessions: [],
            primaryInstruments: [],
            targetRr: nil,
            maxTradesPerDay: nil,
            dailyLossLimit: nil,
            consecutiveLossPause: nil,
            breakevenTolerance: nil,
            dailyProfitTarget: nil,
            maxDrawdownGoal: nil,
            plannedStartMinute: nil,
            plannedEndMinute: nil,
            waitAfterLossMinutes: nil,
            maxRiskPerTrade: nil,
            minAcceptableRr: nil,
            allowedTradingDays: [],
            maxContractsPerTrade: nil,
            maxWeeklyLoss: nil,
            stopAfterDailyProfitTarget: false,
            maxTradesPerDayScope: .combined,
            dailyLossLimitScope: .combined,
            dailyProfitRulesScope: .combined,
            maxWeeklyLossScope: .combined,
            applyRulesToPastTrades: false,
            personalComplianceTargetPercent: nil,
            updatedAt: nil
        )
    }
}

nonisolated struct TradingPreferenceAccountOverride: Equatable, Sendable, Identifiable {
    var userID: ProfileID
    var accountID: TradingAccountID
    var overridesDailyLoss: Bool
    var dailyLossLimit: Double?
    var overridesDailyProfitTarget: Bool
    var dailyProfitTarget: Double?
    var overridesMaxDrawdownGoal: Bool
    var maxDrawdownGoal: Double?
    var updatedAt: Date?

    var id: String { accountID.rawValue }

    static func empty(userID: ProfileID, accountID: TradingAccountID) -> TradingPreferenceAccountOverride {
        TradingPreferenceAccountOverride(
            userID: userID,
            accountID: accountID,
            overridesDailyLoss: false,
            dailyLossLimit: nil,
            overridesDailyProfitTarget: false,
            dailyProfitTarget: nil,
            overridesMaxDrawdownGoal: false,
            maxDrawdownGoal: nil,
            updatedAt: nil
        )
    }
}

nonisolated struct TradingPreferenceRevision: Equatable, Sendable, Identifiable {
    var id: String
    var userID: ProfileID
    var accountID: TradingAccountID?
    var effectiveFrom: Date
    var tradingStyle: TradingStyleID?
    var preferredSessions: [String]
    var primaryInstruments: [String]
    var targetRr: Double?
    var maxTradesPerDay: Int?
    var dailyLossLimit: Double?
    var consecutiveLossPause: Int?
    var breakevenTolerance: Double?
    var dailyProfitTarget: Double?
    var maxDrawdownGoal: Double?
    var plannedStartMinute: Int?
    var plannedEndMinute: Int?
    var waitAfterLossMinutes: Int?
    var maxRiskPerTrade: Double?
    var minAcceptableRr: Double?
    var allowedTradingDays: [String]
    var maxContractsPerTrade: Int?
    var maxWeeklyLoss: Double?
    var stopAfterDailyProfitTarget: Bool
    var maxTradesPerDayScope: TradingRuleScope
    var dailyLossLimitScope: TradingRuleScope
    var dailyProfitRulesScope: TradingRuleScope
    var maxWeeklyLossScope: TradingRuleScope
    var overridesDailyLoss: Bool
    var overridesDailyProfitTarget: Bool
    var overridesMaxDrawdownGoal: Bool
}

/// Rules an analytics engine can read. Nil means the rule is off.
nonisolated struct ResolvedTradingPreferences: Equatable, Sendable {
    var tradingStyle: TradingStyleID?
    var preferredSessions: [String]
    var primaryInstruments: [String]
    var targetRr: Double?
    var maxTradesPerDay: Int?
    var dailyLossLimit: Double?
    var consecutiveLossPause: Int?
    /// Nil keeps exact $0. A value is a ± dollar band.
    var breakevenTolerance: Double?
    var dailyProfitTarget: Double?
    var maxDrawdownGoal: Double?
    var plannedHours: (startMinute: Int, endMinute: Int)?
    var waitAfterLossMinutes: Int?
    var maxRiskPerTrade: Double?
    var minAcceptableRr: Double?
    var allowedTradingDays: [TradingRuleWeekday]
    var maxContractsPerTrade: Int?
    var maxWeeklyLoss: Double?
    var stopAfterDailyProfitTarget: Bool
    var maxTradesPerDayScope: TradingRuleScope
    var dailyLossLimitScope: TradingRuleScope
    var dailyProfitRulesScope: TradingRuleScope
    var maxWeeklyLossScope: TradingRuleScope
    var source: Source

    enum Source: String, Sendable {
        case unset
        case global
        case account
    }

    var hasActiveRuleChecks: Bool {
        if !preferredSessions.isEmpty { return true }
        if !primaryInstruments.isEmpty { return true }
        if plannedHours != nil { return true }
        if !allowedTradingDays.isEmpty { return true }
        if minAcceptableRr != nil { return true }
        if maxContractsPerTrade != nil { return true }
        if maxRiskPerTrade != nil { return true }
        if targetRr != nil { return true }
        if maxTradesPerDay != nil { return true }
        if dailyLossLimit != nil { return true }
        if stopAfterDailyProfitTarget, dailyProfitTarget != nil { return true }
        if maxWeeklyLoss != nil { return true }
        if consecutiveLossPause != nil { return true }
        if let wait = waitAfterLossMinutes, wait > 0 { return true }
        return false
    }

    static var empty: ResolvedTradingPreferences {
        ResolvedTradingPreferences(
            tradingStyle: nil,
            preferredSessions: [],
            primaryInstruments: [],
            targetRr: nil,
            maxTradesPerDay: nil,
            dailyLossLimit: nil,
            consecutiveLossPause: nil,
            breakevenTolerance: nil,
            dailyProfitTarget: nil,
            maxDrawdownGoal: nil,
            plannedHours: nil,
            waitAfterLossMinutes: nil,
            maxRiskPerTrade: nil,
            minAcceptableRr: nil,
            allowedTradingDays: [],
            maxContractsPerTrade: nil,
            maxWeeklyLoss: nil,
            stopAfterDailyProfitTarget: false,
            maxTradesPerDayScope: .combined,
            dailyLossLimitScope: .combined,
            dailyProfitRulesScope: .combined,
            maxWeeklyLossScope: .combined,
            source: .unset
        )
    }

    static func == (lhs: ResolvedTradingPreferences, rhs: ResolvedTradingPreferences) -> Bool {
        lhs.tradingStyle == rhs.tradingStyle
            && lhs.preferredSessions == rhs.preferredSessions
            && lhs.primaryInstruments == rhs.primaryInstruments
            && lhs.targetRr == rhs.targetRr
            && lhs.maxTradesPerDay == rhs.maxTradesPerDay
            && lhs.dailyLossLimit == rhs.dailyLossLimit
            && lhs.consecutiveLossPause == rhs.consecutiveLossPause
            && lhs.breakevenTolerance == rhs.breakevenTolerance
            && lhs.dailyProfitTarget == rhs.dailyProfitTarget
            && lhs.maxDrawdownGoal == rhs.maxDrawdownGoal
            && lhs.plannedHours?.startMinute == rhs.plannedHours?.startMinute
            && lhs.plannedHours?.endMinute == rhs.plannedHours?.endMinute
            && lhs.waitAfterLossMinutes == rhs.waitAfterLossMinutes
            && lhs.maxRiskPerTrade == rhs.maxRiskPerTrade
            && lhs.minAcceptableRr == rhs.minAcceptableRr
            && lhs.allowedTradingDays == rhs.allowedTradingDays
            && lhs.maxContractsPerTrade == rhs.maxContractsPerTrade
            && lhs.maxWeeklyLoss == rhs.maxWeeklyLoss
            && lhs.stopAfterDailyProfitTarget == rhs.stopAfterDailyProfitTarget
            && lhs.maxTradesPerDayScope == rhs.maxTradesPerDayScope
            && lhs.dailyLossLimitScope == rhs.dailyLossLimitScope
            && lhs.dailyProfitRulesScope == rhs.dailyProfitRulesScope
            && lhs.maxWeeklyLossScope == rhs.maxWeeklyLossScope
            && lhs.source == rhs.source
    }
}

nonisolated enum TradingPreferenceRules {
    static let sessions = TradingSessionCatalog.displayOrder

    static func resolve(
        global: TradingPreferenceGlobal?,
        account: TradingPreferenceAccountOverride? = nil
    ) -> ResolvedTradingPreferences {
        guard global != nil || account != nil else { return .empty }
        let usesAccount = account.map {
            $0.overridesDailyLoss || $0.overridesDailyProfitTarget || $0.overridesMaxDrawdownGoal
        } ?? false
        let resolvedDailyProfitTarget = moneyLimit(
            overrides: account?.overridesDailyProfitTarget ?? false,
            overrideAmount: account?.dailyProfitTarget,
            globalAmount: global?.dailyProfitTarget
        )
        return ResolvedTradingPreferences(
            tradingStyle: global?.tradingStyle,
            preferredSessions: global?.preferredSessions ?? [],
            primaryInstruments: global?.primaryInstruments ?? [],
            targetRr: global?.targetRr,
            maxTradesPerDay: global?.maxTradesPerDay,
            dailyLossLimit: moneyLimit(
                overrides: account?.overridesDailyLoss ?? false,
                overrideAmount: account?.dailyLossLimit,
                globalAmount: global?.dailyLossLimit
            ),
            consecutiveLossPause: global?.consecutiveLossPause,
            breakevenTolerance: global?.breakevenTolerance,
            dailyProfitTarget: resolvedDailyProfitTarget,
            maxDrawdownGoal: moneyLimit(
                overrides: account?.overridesMaxDrawdownGoal ?? false,
                overrideAmount: account?.maxDrawdownGoal,
                globalAmount: global?.maxDrawdownGoal
            ),
            plannedHours: plannedHours(
                startMinute: global?.plannedStartMinute,
                endMinute: global?.plannedEndMinute
            ),
            waitAfterLossMinutes: global?.waitAfterLossMinutes,
            maxRiskPerTrade: global?.maxRiskPerTrade,
            minAcceptableRr: global?.minAcceptableRr,
            allowedTradingDays: normalizeAllowedTradingDays(global?.allowedTradingDays ?? []),
            maxContractsPerTrade: global?.maxContractsPerTrade,
            maxWeeklyLoss: global?.maxWeeklyLoss,
            stopAfterDailyProfitTarget:
                (global?.stopAfterDailyProfitTarget ?? false) && resolvedDailyProfitTarget != nil,
            maxTradesPerDayScope: TradingRuleScopeMath.normalizeScope(global?.maxTradesPerDayScope.rawValue),
            dailyLossLimitScope: TradingRuleScopeMath.normalizeScope(global?.dailyLossLimitScope.rawValue),
            dailyProfitRulesScope: TradingRuleScopeMath.normalizeScope(global?.dailyProfitRulesScope.rawValue),
            maxWeeklyLossScope: TradingRuleScopeMath.normalizeScope(global?.maxWeeklyLossScope.rawValue),
            source: usesAccount ? .account : (global == nil ? .unset : .global)
        )
    }

    /// Rules saved at `at`. A time before the first save has no personal rule.
    static func activeAt(
        _ revisions: [TradingPreferenceRevision],
        at: Date,
        accountID: TradingAccountID? = nil
    ) -> ResolvedTradingPreferences {
        let global = latest(revisions.filter { $0.accountID == nil }, at: at)
        let account = accountID.flatMap { id in
            latest(revisions.filter { $0.accountID == id }, at: at)
        }
        return resolve(
            global: global.map(globalSnapshot),
            account: account.flatMap(overrideSnapshot)
        )
    }

    static func normalizeInstruments(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var next: [String] = []
        for value in values {
            let symbol = value.trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
                .replacingOccurrences(of: " ", with: "")
            guard symbol.range(of: "^[A-Z0-9./-]{1,16}$", options: .regularExpression) != nil,
                  seen.insert(symbol).inserted
            else { continue }
            next.append(symbol)
            if next.count == 12 { break }
        }
        return next
    }

    static func normalizeSessions(_ values: [String]) -> [String] {
        let allowed = Set(sessions)
        let selected = Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        return sessions.filter { allowed.contains($0) && selected.contains($0) }
    }

    static func normalizeAllowedTradingDays(_ values: [String]) -> [TradingRuleWeekday] {
        TradingRuleScopeMath.normalizeAllowedTradingDays(values)
    }

    private static func moneyLimit(
        overrides: Bool,
        overrideAmount: Double?,
        globalAmount: Double?
    ) -> Double? {
        overrides ? overrideAmount : globalAmount
    }

    private static func plannedHours(
        startMinute: Int?,
        endMinute: Int?
    ) -> (startMinute: Int, endMinute: Int)? {
        guard let startMinute, let endMinute, startMinute != endMinute else { return nil }
        return (startMinute, endMinute)
    }

    private static func latest(
        _ rows: [TradingPreferenceRevision],
        at: Date
    ) -> TradingPreferenceRevision? {
        rows.filter { $0.effectiveFrom <= at }.max { $0.effectiveFrom < $1.effectiveFrom }
    }

    private static func globalSnapshot(_ row: TradingPreferenceRevision) -> TradingPreferenceGlobal {
        TradingPreferenceGlobal(
            userID: row.userID,
            tradingStyle: row.tradingStyle,
            preferredSessions: row.preferredSessions,
            primaryInstruments: row.primaryInstruments,
            targetRr: row.targetRr,
            maxTradesPerDay: row.maxTradesPerDay,
            dailyLossLimit: row.dailyLossLimit,
            consecutiveLossPause: row.consecutiveLossPause,
            breakevenTolerance: row.breakevenTolerance,
            dailyProfitTarget: row.dailyProfitTarget,
            maxDrawdownGoal: row.maxDrawdownGoal,
            plannedStartMinute: row.plannedStartMinute,
            plannedEndMinute: row.plannedEndMinute,
            waitAfterLossMinutes: row.waitAfterLossMinutes,
            maxRiskPerTrade: row.maxRiskPerTrade,
            minAcceptableRr: row.minAcceptableRr,
            allowedTradingDays: row.allowedTradingDays,
            maxContractsPerTrade: row.maxContractsPerTrade,
            maxWeeklyLoss: row.maxWeeklyLoss,
            stopAfterDailyProfitTarget: row.stopAfterDailyProfitTarget,
            maxTradesPerDayScope: row.maxTradesPerDayScope,
            dailyLossLimitScope: row.dailyLossLimitScope,
            dailyProfitRulesScope: row.dailyProfitRulesScope,
            maxWeeklyLossScope: row.maxWeeklyLossScope,
            applyRulesToPastTrades: false,
            updatedAt: row.effectiveFrom
        )
    }

    private static func overrideSnapshot(
        _ row: TradingPreferenceRevision
    ) -> TradingPreferenceAccountOverride? {
        guard let accountID = row.accountID else { return nil }
        return TradingPreferenceAccountOverride(
            userID: row.userID,
            accountID: accountID,
            overridesDailyLoss: row.overridesDailyLoss,
            dailyLossLimit: row.dailyLossLimit,
            overridesDailyProfitTarget: row.overridesDailyProfitTarget,
            dailyProfitTarget: row.dailyProfitTarget,
            overridesMaxDrawdownGoal: row.overridesMaxDrawdownGoal,
            maxDrawdownGoal: row.maxDrawdownGoal,
            updatedAt: row.effectiveFrom
        )
    }
}
