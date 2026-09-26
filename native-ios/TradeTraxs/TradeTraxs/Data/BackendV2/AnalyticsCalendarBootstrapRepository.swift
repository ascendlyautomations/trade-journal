import Foundation

nonisolated enum AnalyticsCalendarBootstrapLoader {
    static func loadDailyRange(
        rpc: any RPCClient,
        start: String,
        end: String,
        accountID: String? = nil,
        mode: String? = nil
    ) async throws -> AnalyticsDailyRangeBootstrapV1 {
        var args: [String: Any] = [
            "p_start": start,
            "p_end": end,
        ]
        if let accountID {
            args["p_account_id"] = accountID
        }
        if let mode {
            args["p_mode"] = mode
        }
        let data = try SupabaseJSONEncoding.data(fromJSONObject: args)
        let client = BackendV2RPCClient(transport: rpc, enforceKnownNames: false)
        return try await client.call(
            BackendV2Versioning.RPCName.analyticsDailyRangeBootstrap.rawValue,
            argumentsJSON: data,
            as: AnalyticsDailyRangeBootstrapV1.self,
            options: BackendV2RPCCallOptions(
                flagName: BackendV2FeatureFlag.calendarAnalyticsV2.dottedName
            )
        )
    }

    static func loadDayTrades(
        rpc: any RPCClient,
        calendarDay: String,
        accountID: String? = nil,
        mode: String? = nil
    ) async throws -> AnalyticsCalendarDayTradesBootstrapV1 {
        var args: [String: Any] = ["p_calendar_day": calendarDay]
        if let accountID {
            args["p_account_id"] = accountID
        }
        if let mode {
            args["p_mode"] = mode
        }
        let data = try SupabaseJSONEncoding.data(fromJSONObject: args)
        let client = BackendV2RPCClient(transport: rpc, enforceKnownNames: false)
        return try await client.call(
            BackendV2Versioning.RPCName.analyticsCalendarDayTrades.rawValue,
            argumentsJSON: data,
            as: AnalyticsCalendarDayTradesBootstrapV1.self,
            options: BackendV2RPCCallOptions(
                flagName: BackendV2FeatureFlag.calendarAnalyticsV2.dottedName
            )
        )
    }

    static func mapDayTrades(
        _ rows: [DashboardTradeWireV1],
        ownerID: ProfileID
    ) -> [Trade] {
        mapDayTradeSummaries(rows, ownerID: ownerID).map(TradeSummaryMapper.previewTrade(from:))
    }

    static func mapDayTradeSummaries(
        _ rows: [DashboardTradeWireV1],
        ownerID: ProfileID
    ) -> [TradeSummary] {
        TradeSummaryCalendarMapper.mapDayTrades(rows, ownerID: ownerID)
    }
}
