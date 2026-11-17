import Foundation

nonisolated struct DefaultTradingPreferencesRepository: TradingPreferencesRepository {
    private let supabase: SupabaseInfrastructure

    init(supabase: SupabaseInfrastructure) {
        self.supabase = supabase
    }

    func globalPreferences(for userID: ProfileID) async throws -> TradingPreferenceGlobal {
        let rows: [GlobalDTO] = try await supabase.database.select(
            GlobalDTO.self,
            from: "trading_preferences",
            query: [
                SupabaseQuery.select(GlobalDTO.columns),
                SupabaseQuery.eq("user_id", userID.rawValue),
                URLQueryItem(name: "limit", value: "1"),
            ]
        )
        return rows.first?.model(fallback: userID) ?? .empty(userID: userID)
    }

    func saveGlobal(_ preferences: TradingPreferenceGlobal) async throws -> TradingPreferenceGlobal {
        do {
            let saved: GlobalDTO = try await supabase.database.upsert(
                GlobalWrite(preferences: preferences),
                into: "trading_preferences",
                onConflict: "user_id",
                returning: GlobalDTO.self,
                select: GlobalDTO.columns
            )
            return saved.model(fallback: preferences.userID)
        } catch {
            if let recovered = try? await globalPreferences(for: preferences.userID),
               recovered.updatedAt != nil || tradingPreferencesRowMatches(recovered, expected: preferences)
            {
                return recovered
            }
            throw error
        }
    }

    func accountOverrides(for userID: ProfileID) async throws -> [TradingPreferenceAccountOverride] {
        let rows: [OverrideDTO] = try await supabase.database.select(
            OverrideDTO.self,
            from: "trading_preference_account_overrides",
            query: [
                SupabaseQuery.select(OverrideDTO.columns),
                SupabaseQuery.eq("user_id", userID.rawValue),
            ]
        )
        return rows.map { $0.model(fallback: userID) }
    }

    func saveOverride(
        _ override: TradingPreferenceAccountOverride
    ) async throws -> TradingPreferenceAccountOverride {
        do {
            let saved: OverrideDTO = try await supabase.database.upsert(
                OverrideWrite(override: override),
                into: "trading_preference_account_overrides",
                onConflict: "user_id,account_id",
                returning: OverrideDTO.self,
                select: OverrideDTO.columns
            )
            return saved.model(fallback: override.userID)
        } catch {
            let rows = (try? await accountOverrides(for: override.userID)) ?? []
            if let recovered = rows.first(where: { $0.accountID == override.accountID }),
               recovered == override
            {
                return recovered
            }
            throw error
        }
    }

    func revisions(for userID: ProfileID) async throws -> [TradingPreferenceRevision] {
        let rows: [RevisionDTO] = try await supabase.database.select(
            RevisionDTO.self,
            from: "trading_preference_revisions",
            query: [
                SupabaseQuery.select(RevisionDTO.columns),
                SupabaseQuery.eq("user_id", userID.rawValue),
                SupabaseQuery.order("effective_from", ascending: true),
            ]
        )
        return rows.compactMap { $0.model(fallback: userID) }
    }

    func discovery(for userID: ProfileID) async throws -> PreferenceDiscoveryResponse? {
        let rows: [DiscoveryDTO] = try await supabase.database.select(
            DiscoveryDTO.self,
            from: "trading_preference_discovery",
            query: [
                SupabaseQuery.select("response"),
                SupabaseQuery.eq("user_id", userID.rawValue),
                SupabaseQuery.limit(1),
            ]
        )
        return rows.first?.response.flatMap(PreferenceDiscoveryResponse.init(rawValue:))
    }

    func recordDiscovery(
        _ response: PreferenceDiscoveryResponse,
        for userID: ProfileID
    ) async throws -> PreferenceDiscoveryResponse {
        if let current = try await discovery(for: userID), current.rank >= response.rank {
            return current
        }
        let saved: DiscoveryDTO = try await supabase.database.upsert(
            DiscoveryWrite(userID: userID, response: response),
            into: "trading_preference_discovery",
            onConflict: "user_id",
            returning: DiscoveryDTO.self,
            select: "response"
        )
        return saved.response.flatMap(PreferenceDiscoveryResponse.init(rawValue:)) ?? response
    }

    func hasJournalTrade(for userID: ProfileID) async throws -> Bool {
        let rows: [TradeIDRow] = try await supabase.database.select(
            TradeIDRow.self,
            from: "trades",
            query: [
                SupabaseQuery.select("id"),
                SupabaseQuery.eq("user_id", userID.rawValue),
                SupabaseQuery.neq("mode", "backtest"),
                SupabaseQuery.limit(1),
            ]
        )
        return !rows.isEmpty
    }
}

private nonisolated struct GlobalDTO: Decodable, Sendable {
    static let columns = [
        "user_id", "trading_style", "preferred_sessions", "primary_instruments",
        "target_rr", "max_trades_per_day", "daily_loss_limit", "consecutive_loss_pause",
        "breakeven_tolerance", "daily_profit_target", "max_drawdown_goal",
        "planned_start_minute", "planned_end_minute", "wait_after_loss_minutes",
        "max_risk_per_trade", "min_acceptable_rr", "allowed_trading_days", "max_contracts_per_trade",
        "max_weekly_loss", "stop_after_daily_profit_target",
        "max_trades_per_day_scope", "daily_loss_limit_scope", "daily_profit_rules_scope",
        "max_weekly_loss_scope", "apply_rules_to_past_trades", "personal_compliance_target_percent", "updated_at",
    ].joined(separator: ",")

    var user_id: String?
    var trading_style: String?
    var preferred_sessions: [String]?
    var primary_instruments: [String]?
    var target_rr: PostgresFlexibleDouble?
    var max_trades_per_day: PostgresFlexibleDouble?
    var daily_loss_limit: PostgresFlexibleDouble?
    var consecutive_loss_pause: PostgresFlexibleDouble?
    var breakeven_tolerance: PostgresFlexibleDouble?
    var daily_profit_target: PostgresFlexibleDouble?
    var max_drawdown_goal: PostgresFlexibleDouble?
    var planned_start_minute: PostgresFlexibleDouble?
    var planned_end_minute: PostgresFlexibleDouble?
    var wait_after_loss_minutes: PostgresFlexibleDouble?
    var max_risk_per_trade: PostgresFlexibleDouble?
    var min_acceptable_rr: PostgresFlexibleDouble?
    var allowed_trading_days: [String]?
    var max_contracts_per_trade: PostgresFlexibleDouble?
    var max_weekly_loss: PostgresFlexibleDouble?
    var stop_after_daily_profit_target: Bool?
    var max_trades_per_day_scope: String?
    var daily_loss_limit_scope: String?
    var daily_profit_rules_scope: String?
    var max_weekly_loss_scope: String?
    var apply_rules_to_past_trades: Bool?
    var personal_compliance_target_percent: PostgresFlexibleDouble?
    var updated_at: String?

    func model(fallback: ProfileID) -> TradingPreferenceGlobal {
        TradingPreferenceGlobal(
            userID: ProfileID(user_id ?? fallback.rawValue),
            tradingStyle: trading_style.flatMap(TradingStyleID.init(rawValue:)),
            preferredSessions: TradingPreferenceRules.normalizeSessions(preferred_sessions ?? []),
            primaryInstruments: TradingPreferenceRules.normalizeInstruments(primary_instruments ?? []),
            targetRr: target_rr?.value,
            maxTradesPerDay: max_trades_per_day?.value.map { Int($0) },
            dailyLossLimit: daily_loss_limit?.value,
            consecutiveLossPause: consecutive_loss_pause?.value.map { Int($0) },
            breakevenTolerance: breakeven_tolerance?.value,
            dailyProfitTarget: daily_profit_target?.value,
            maxDrawdownGoal: max_drawdown_goal?.value,
            plannedStartMinute: planned_start_minute?.value.map { Int($0) },
            plannedEndMinute: planned_end_minute?.value.map { Int($0) },
            waitAfterLossMinutes: wait_after_loss_minutes?.value.map { Int($0) },
            maxRiskPerTrade: max_risk_per_trade?.value,
            minAcceptableRr: min_acceptable_rr?.value,
            allowedTradingDays: TradingRuleScopeMath.normalizeAllowedTradingDays(allowed_trading_days ?? [])
                .map(\.rawValue),
            maxContractsPerTrade: max_contracts_per_trade?.value.map { Int($0) },
            maxWeeklyLoss: max_weekly_loss?.value,
            stopAfterDailyProfitTarget: stop_after_daily_profit_target ?? false,
            maxTradesPerDayScope: TradingRuleScopeMath.normalizeScope(max_trades_per_day_scope),
            dailyLossLimitScope: TradingRuleScopeMath.normalizeScope(daily_loss_limit_scope),
            dailyProfitRulesScope: TradingRuleScopeMath.normalizeScope(daily_profit_rules_scope),
            maxWeeklyLossScope: TradingRuleScopeMath.normalizeScope(max_weekly_loss_scope),
            applyRulesToPastTrades: apply_rules_to_past_trades ?? false,
            personalComplianceTargetPercent: personal_compliance_target_percent?.value,
            updatedAt: updated_at.flatMap(ISO8601.date(from:))
        )
    }
}

private nonisolated struct OverrideDTO: Decodable, Sendable {
    static let columns = [
        "user_id", "account_id", "overrides_daily_loss", "daily_loss_limit",
        "overrides_daily_profit_target", "daily_profit_target",
        "overrides_max_drawdown_goal", "max_drawdown_goal", "updated_at",
    ].joined(separator: ",")

    var user_id: String?
    var account_id: String?
    var overrides_daily_loss: Bool?
    var daily_loss_limit: PostgresFlexibleDouble?
    var overrides_daily_profit_target: Bool?
    var daily_profit_target: PostgresFlexibleDouble?
    var overrides_max_drawdown_goal: Bool?
    var max_drawdown_goal: PostgresFlexibleDouble?
    var updated_at: String?

    func model(fallback: ProfileID) -> TradingPreferenceAccountOverride {
        TradingPreferenceAccountOverride(
            userID: ProfileID(user_id ?? fallback.rawValue),
            accountID: TradingAccountID(account_id ?? ""),
            overridesDailyLoss: overrides_daily_loss ?? false,
            dailyLossLimit: daily_loss_limit?.value,
            overridesDailyProfitTarget: overrides_daily_profit_target ?? false,
            dailyProfitTarget: daily_profit_target?.value,
            overridesMaxDrawdownGoal: overrides_max_drawdown_goal ?? false,
            maxDrawdownGoal: max_drawdown_goal?.value,
            updatedAt: updated_at.flatMap(ISO8601.date(from:))
        )
    }
}

private nonisolated struct RevisionDTO: Decodable, Sendable {
    static let columns = [
        "id", "user_id", "account_id", "effective_from", "trading_style",
        "preferred_sessions", "primary_instruments", "target_rr", "max_trades_per_day",
        "daily_loss_limit", "consecutive_loss_pause", "breakeven_tolerance",
        "daily_profit_target", "max_drawdown_goal", "planned_start_minute",
        "planned_end_minute", "wait_after_loss_minutes",
        "max_risk_per_trade", "min_acceptable_rr", "allowed_trading_days", "max_contracts_per_trade",
        "max_weekly_loss", "stop_after_daily_profit_target",
        "max_trades_per_day_scope", "daily_loss_limit_scope", "daily_profit_rules_scope",
        "max_weekly_loss_scope",
        "overrides_daily_loss", "overrides_daily_profit_target", "overrides_max_drawdown_goal",
    ].joined(separator: ",")

    var id: String?
    var user_id: String?
    var account_id: String?
    var effective_from: String?
    var trading_style: String?
    var preferred_sessions: [String]?
    var primary_instruments: [String]?
    var target_rr: PostgresFlexibleDouble?
    var max_trades_per_day: PostgresFlexibleDouble?
    var daily_loss_limit: PostgresFlexibleDouble?
    var consecutive_loss_pause: PostgresFlexibleDouble?
    var breakeven_tolerance: PostgresFlexibleDouble?
    var daily_profit_target: PostgresFlexibleDouble?
    var max_drawdown_goal: PostgresFlexibleDouble?
    var planned_start_minute: PostgresFlexibleDouble?
    var planned_end_minute: PostgresFlexibleDouble?
    var wait_after_loss_minutes: PostgresFlexibleDouble?
    var max_risk_per_trade: PostgresFlexibleDouble?
    var min_acceptable_rr: PostgresFlexibleDouble?
    var allowed_trading_days: [String]?
    var max_contracts_per_trade: PostgresFlexibleDouble?
    var max_weekly_loss: PostgresFlexibleDouble?
    var stop_after_daily_profit_target: Bool?
    var max_trades_per_day_scope: String?
    var daily_loss_limit_scope: String?
    var daily_profit_rules_scope: String?
    var max_weekly_loss_scope: String?
    var overrides_daily_loss: Bool?
    var overrides_daily_profit_target: Bool?
    var overrides_max_drawdown_goal: Bool?

    func model(fallback: ProfileID) -> TradingPreferenceRevision? {
        guard let effective = effective_from.flatMap(ISO8601.date(from:)) else { return nil }
        return TradingPreferenceRevision(
            id: id ?? UUID().uuidString,
            userID: ProfileID(user_id ?? fallback.rawValue),
            accountID: account_id.map { TradingAccountID(rawValue: $0) },
            effectiveFrom: effective,
            tradingStyle: trading_style.flatMap(TradingStyleID.init(rawValue:)),
            preferredSessions: TradingPreferenceRules.normalizeSessions(preferred_sessions ?? []),
            primaryInstruments: TradingPreferenceRules.normalizeInstruments(primary_instruments ?? []),
            targetRr: target_rr?.value,
            maxTradesPerDay: max_trades_per_day?.value.map { Int($0) },
            dailyLossLimit: daily_loss_limit?.value,
            consecutiveLossPause: consecutive_loss_pause?.value.map { Int($0) },
            breakevenTolerance: breakeven_tolerance?.value,
            dailyProfitTarget: daily_profit_target?.value,
            maxDrawdownGoal: max_drawdown_goal?.value,
            plannedStartMinute: planned_start_minute?.value.map { Int($0) },
            plannedEndMinute: planned_end_minute?.value.map { Int($0) },
            waitAfterLossMinutes: wait_after_loss_minutes?.value.map { Int($0) },
            maxRiskPerTrade: max_risk_per_trade?.value,
            minAcceptableRr: min_acceptable_rr?.value,
            allowedTradingDays: TradingRuleScopeMath.normalizeAllowedTradingDays(allowed_trading_days ?? [])
                .map(\.rawValue),
            maxContractsPerTrade: max_contracts_per_trade?.value.map { Int($0) },
            maxWeeklyLoss: max_weekly_loss?.value,
            stopAfterDailyProfitTarget: stop_after_daily_profit_target ?? false,
            maxTradesPerDayScope: TradingRuleScopeMath.normalizeScope(max_trades_per_day_scope),
            dailyLossLimitScope: TradingRuleScopeMath.normalizeScope(daily_loss_limit_scope),
            dailyProfitRulesScope: TradingRuleScopeMath.normalizeScope(daily_profit_rules_scope),
            maxWeeklyLossScope: TradingRuleScopeMath.normalizeScope(max_weekly_loss_scope),
            overridesDailyLoss: overrides_daily_loss ?? false,
            overridesDailyProfitTarget: overrides_daily_profit_target ?? false,
            overridesMaxDrawdownGoal: overrides_max_drawdown_goal ?? false
        )
    }
}

private nonisolated struct GlobalWrite: Encodable, Sendable {
    var preferences: TradingPreferenceGlobal

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(preferences.userID.rawValue, forKey: .user_id)
        try encodeOptional(preferences.tradingStyle?.rawValue, forKey: .trading_style, into: &container)
        try container.encode(preferences.preferredSessions, forKey: .preferred_sessions)
        try container.encode(preferences.primaryInstruments, forKey: .primary_instruments)
        try encodeOptional(preferences.targetRr, forKey: .target_rr, into: &container)
        try encodeOptional(preferences.maxTradesPerDay, forKey: .max_trades_per_day, into: &container)
        try encodeOptional(preferences.dailyLossLimit, forKey: .daily_loss_limit, into: &container)
        try encodeOptional(preferences.consecutiveLossPause, forKey: .consecutive_loss_pause, into: &container)
        try encodeOptional(preferences.breakevenTolerance, forKey: .breakeven_tolerance, into: &container)
        try encodeOptional(preferences.dailyProfitTarget, forKey: .daily_profit_target, into: &container)
        try encodeOptional(preferences.maxDrawdownGoal, forKey: .max_drawdown_goal, into: &container)
        try encodeOptional(preferences.plannedStartMinute, forKey: .planned_start_minute, into: &container)
        try encodeOptional(preferences.plannedEndMinute, forKey: .planned_end_minute, into: &container)
        try encodeOptional(preferences.waitAfterLossMinutes, forKey: .wait_after_loss_minutes, into: &container)
        try encodeOptional(preferences.maxRiskPerTrade, forKey: .max_risk_per_trade, into: &container)
        try encodeOptional(preferences.minAcceptableRr, forKey: .min_acceptable_rr, into: &container)
        try container.encode(preferences.allowedTradingDays, forKey: .allowed_trading_days)
        try encodeOptional(preferences.maxContractsPerTrade, forKey: .max_contracts_per_trade, into: &container)
        try encodeOptional(preferences.maxWeeklyLoss, forKey: .max_weekly_loss, into: &container)
        try container.encode(preferences.stopAfterDailyProfitTarget, forKey: .stop_after_daily_profit_target)
        try container.encode(preferences.maxTradesPerDayScope.rawValue, forKey: .max_trades_per_day_scope)
        try container.encode(preferences.dailyLossLimitScope.rawValue, forKey: .daily_loss_limit_scope)
        try container.encode(preferences.dailyProfitRulesScope.rawValue, forKey: .daily_profit_rules_scope)
        try container.encode(preferences.maxWeeklyLossScope.rawValue, forKey: .max_weekly_loss_scope)
        try container.encode(preferences.applyRulesToPastTrades, forKey: .apply_rules_to_past_trades)
        try encodeOptional(preferences.personalComplianceTargetPercent, forKey: .personal_compliance_target_percent, into: &container)
    }

    private enum CodingKeys: String, CodingKey {
        case user_id, trading_style, preferred_sessions, primary_instruments, target_rr
        case max_trades_per_day, daily_loss_limit, consecutive_loss_pause, breakeven_tolerance
        case daily_profit_target, max_drawdown_goal, planned_start_minute, planned_end_minute
        case wait_after_loss_minutes, max_risk_per_trade, min_acceptable_rr, allowed_trading_days
        case max_contracts_per_trade, max_weekly_loss, stop_after_daily_profit_target
        case max_trades_per_day_scope, daily_loss_limit_scope, daily_profit_rules_scope, max_weekly_loss_scope
        case apply_rules_to_past_trades
        case personal_compliance_target_percent
    }
}

private nonisolated struct OverrideWrite: Encodable, Sendable {
    var override: TradingPreferenceAccountOverride

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(override.userID.rawValue, forKey: .user_id)
        try container.encode(override.accountID.rawValue, forKey: .account_id)
        try container.encode(override.overridesDailyLoss, forKey: .overrides_daily_loss)
        try encodeOptional(
            override.overridesDailyLoss ? override.dailyLossLimit : nil,
            forKey: .daily_loss_limit,
            into: &container
        )
        try container.encode(override.overridesDailyProfitTarget, forKey: .overrides_daily_profit_target)
        try encodeOptional(
            override.overridesDailyProfitTarget ? override.dailyProfitTarget : nil,
            forKey: .daily_profit_target,
            into: &container
        )
        try container.encode(override.overridesMaxDrawdownGoal, forKey: .overrides_max_drawdown_goal)
        try encodeOptional(
            override.overridesMaxDrawdownGoal ? override.maxDrawdownGoal : nil,
            forKey: .max_drawdown_goal,
            into: &container
        )
    }

    private enum CodingKeys: String, CodingKey {
        case user_id, account_id, overrides_daily_loss, daily_loss_limit
        case overrides_daily_profit_target, daily_profit_target
        case overrides_max_drawdown_goal, max_drawdown_goal
    }
}

private nonisolated func encodeOptional<T: Encodable & Sendable, Key: CodingKey>(
    _ value: T?,
    forKey key: Key,
    into container: inout KeyedEncodingContainer<Key>
) throws {
    if let value {
        try container.encode(value, forKey: key)
    } else {
        try container.encodeNil(forKey: key)
    }
}

private nonisolated struct DiscoveryDTO: Decodable, Sendable {
    var response: String?
}

private nonisolated struct DiscoveryWrite: Encodable, Sendable {
    var userID: ProfileID
    var response: PreferenceDiscoveryResponse

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID.rawValue, forKey: .user_id)
        try container.encode(response.rawValue, forKey: .response)
    }

    private enum CodingKeys: String, CodingKey {
        case user_id
        case response
    }
}

private nonisolated struct TradeIDRow: Decodable, Sendable {
    var id: String
}

/// When PostgREST returns a row the client fails to decode, confirm the write via SELECT.
private nonisolated func tradingPreferencesRowMatches(
    _ persisted: TradingPreferenceGlobal,
    expected: TradingPreferenceGlobal
) -> Bool {
    persisted.userID == expected.userID
        && persisted.tradingStyle == expected.tradingStyle
        && persisted.preferredSessions == expected.preferredSessions
        && persisted.primaryInstruments == expected.primaryInstruments
        && persisted.targetRr == expected.targetRr
        && persisted.maxTradesPerDay == expected.maxTradesPerDay
        && persisted.dailyLossLimit == expected.dailyLossLimit
        && persisted.consecutiveLossPause == expected.consecutiveLossPause
        && persisted.breakevenTolerance == expected.breakevenTolerance
        && persisted.dailyProfitTarget == expected.dailyProfitTarget
        && persisted.maxDrawdownGoal == expected.maxDrawdownGoal
        && persisted.plannedStartMinute == expected.plannedStartMinute
        && persisted.plannedEndMinute == expected.plannedEndMinute
        && persisted.waitAfterLossMinutes == expected.waitAfterLossMinutes
        && persisted.maxRiskPerTrade == expected.maxRiskPerTrade
        && persisted.minAcceptableRr == expected.minAcceptableRr
        && persisted.allowedTradingDays == expected.allowedTradingDays
        && persisted.maxContractsPerTrade == expected.maxContractsPerTrade
        && persisted.maxWeeklyLoss == expected.maxWeeklyLoss
        && persisted.stopAfterDailyProfitTarget == expected.stopAfterDailyProfitTarget
        && persisted.maxTradesPerDayScope == expected.maxTradesPerDayScope
        && persisted.dailyLossLimitScope == expected.dailyLossLimitScope
        && persisted.dailyProfitRulesScope == expected.dailyProfitRulesScope
        && persisted.maxWeeklyLossScope == expected.maxWeeklyLossScope
        && persisted.applyRulesToPastTrades == expected.applyRulesToPastTrades
        && persisted.personalComplianceTargetPercent == expected.personalComplianceTargetPercent
}
