import Foundation

nonisolated struct AnalyticsDailyStatRowV1: Codable, Sendable, Equatable {
    var calendar_day: String
    var account_id: String?
    var mode_effective: String?
    var trade_count: Int
    var win_count: Int
    var loss_count: Int
    var breakeven_count: Int
    var net_pnl: PostgresFlexibleDouble
    var gross_profit: PostgresFlexibleDouble
    var gross_loss: PostgresFlexibleDouble
    var long_count: Int?
    var long_pnl: PostgresFlexibleDouble?
    var short_count: Int?
    var short_pnl: PostgresFlexibleDouble?
    var sum_rr: PostgresFlexibleDouble?
    var rr_count: Int?
    var sum_hold_seconds: PostgresFlexibleDouble?
    var hold_count: Int?
    var largest_win: PostgresFlexibleDouble?
    var largest_loss: PostgresFlexibleDouble?
}

nonisolated struct AnalyticsDailyRangeSummaryV1: Codable, Sendable, Equatable {
    var trade_count: Int
    var win_count: Int
    var loss_count: Int
    var breakeven_count: Int
    var net_pnl: PostgresFlexibleDouble
    var gross_profit: PostgresFlexibleDouble
    var gross_loss: PostgresFlexibleDouble
}

nonisolated struct AnalyticsDailyRangeBootstrapV1: Codable, Sendable, Equatable {
    var revision: PostgresFlexibleDouble?
    var state_updated_at: String?
    var start: String
    var end: String
    var account_id: String?
    var mode: String?
    var days: [AnalyticsDailyStatRowV1]
    var summary: AnalyticsDailyRangeSummaryV1

    var revisionInt: Int64 {
        Int64(revision?.value ?? 0)
    }
}

nonisolated struct AnalyticsCalendarDayAggregateV1: Codable, Sendable, Equatable {
    var trade_count: Int
    var win_count: Int
    var loss_count: Int
    var breakeven_count: Int
    var net_pnl: PostgresFlexibleDouble
    var gross_profit: PostgresFlexibleDouble
    var gross_loss: PostgresFlexibleDouble
}

nonisolated struct AnalyticsCalendarDayTradesBootstrapV1: Codable, Sendable, Equatable {
    var revision: PostgresFlexibleDouble?
    var calendar_day: String
    var aggregate: AnalyticsCalendarDayAggregateV1
    var trades: [DashboardTradeWireV1]
}
