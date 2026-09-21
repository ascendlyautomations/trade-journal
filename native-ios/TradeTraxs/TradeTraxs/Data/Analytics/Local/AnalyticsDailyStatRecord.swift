import Foundation
import GRDB

struct AnalyticsDailyStatRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "analytics_daily_stat"

    var viewer_id: String
    var calendar_day: String
    var mode_effective: String
    var account_scope_key: String
    var trade_count: Int
    var win_count: Int
    var loss_count: Int
    var breakeven_count: Int
    var net_pnl: Double
    var gross_profit: Double
    var gross_loss: Double
    var long_count: Int
    var long_pnl: Double
    var short_count: Int
    var short_pnl: Double
    var sum_rr: Double
    var rr_count: Int
    var sum_hold_seconds: Double
    var hold_count: Int
    var largest_win: Double?
    var largest_loss: Double?
    var ingested_revision: Int64

    static func from(row: AnalyticsDailyStatRowV1, viewerID: String, ingestedRevision: Int64) -> AnalyticsDailyStatRecord {
        AnalyticsDailyStatRecord(
            viewer_id: viewerID,
            calendar_day: row.calendar_day,
            mode_effective: row.mode_effective ?? "unknown",
            account_scope_key: AnalyticsScopeKeys.accountScopeKey(forRowAccountID: row.account_id),
            trade_count: row.trade_count,
            win_count: row.win_count,
            loss_count: row.loss_count,
            breakeven_count: row.breakeven_count,
            net_pnl: row.net_pnl.value ?? 0,
            gross_profit: row.gross_profit.value ?? 0,
            gross_loss: row.gross_loss.value ?? 0,
            long_count: row.long_count ?? 0,
            long_pnl: row.long_pnl?.value ?? 0,
            short_count: row.short_count ?? 0,
            short_pnl: row.short_pnl?.value ?? 0,
            sum_rr: row.sum_rr?.value ?? 0,
            rr_count: row.rr_count ?? 0,
            sum_hold_seconds: row.sum_hold_seconds?.value ?? 0,
            hold_count: row.hold_count ?? 0,
            largest_win: row.largest_win?.value,
            largest_loss: row.largest_loss?.value,
            ingested_revision: ingestedRevision
        )
    }

    func identityKey() -> String {
        "\(calendar_day)|\(mode_effective)|\(account_scope_key)"
    }
}

struct AnalyticsRangeCoverageRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "analytics_range_coverage"

    var viewer_id: String
    var domain: String
    var account_scope: String
    var mode_scope: String
    var start_date: String
    var end_date: String
    var server_revision: Int64
    var fetched_at: String
}

struct AnalyticsSyncStateRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "analytics_sync_state"

    var viewer_id: String
    var server_revision: Int64
    var updated_at: String
    var local_schema_version: Int
}
