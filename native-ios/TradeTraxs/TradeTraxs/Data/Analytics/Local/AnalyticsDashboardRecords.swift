import Foundation
import GRDB

struct DashboardPresetMetricsRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "dashboard_preset_metrics"

    var viewer_id: String
    var scope: String
    var account_scope_key: String
    var preset_key: String
    var preset_start: String
    var preset_end: String
    var as_of_et: String
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

    static func fromAggregate(
        presetKey: String,
        bundle: AnalyticsDashboardPresetBundleV1,
        viewerID: String,
        asOfET: String,
        revision: Int64
    ) -> DashboardPresetMetricsRecord {
        fromMetrics(
            presetKey: presetKey,
            metricsPreset: AnalyticsDashboardMetricsPresetV1(
                preset: bundle.preset,
                start: bundle.start,
                end: bundle.end,
                metrics: bundle.metrics
            ),
            viewerID: viewerID,
            scope: AnalyticsLocalSchema.scopeAggregate,
            accountScopeKey: AnalyticsScopeKeys.allAccountsQuery,
            asOfET: asOfET,
            revision: revision
        )
    }

    static func fromAccount(
        accountID: String,
        presetKey: String,
        metricsPreset: AnalyticsDashboardMetricsPresetV1,
        viewerID: String,
        asOfET: String,
        revision: Int64
    ) -> DashboardPresetMetricsRecord {
        fromMetrics(
            presetKey: presetKey,
            metricsPreset: metricsPreset,
            viewerID: viewerID,
            scope: AnalyticsLocalSchema.scopeAccount,
            accountScopeKey: AnalyticsScopeKeys.accountScopeKey(forQueryAccountID: accountID),
            asOfET: asOfET,
            revision: revision
        )
    }

    private static func fromMetrics(
        presetKey: String,
        metricsPreset: AnalyticsDashboardMetricsPresetV1,
        viewerID: String,
        scope: String,
        accountScopeKey: String,
        asOfET: String,
        revision: Int64
    ) -> DashboardPresetMetricsRecord {
        let m = metricsPreset.metrics
        return DashboardPresetMetricsRecord(
            viewer_id: viewerID,
            scope: scope,
            account_scope_key: accountScopeKey,
            preset_key: presetKey,
            preset_start: metricsPreset.start,
            preset_end: metricsPreset.end,
            as_of_et: asOfET,
            trade_count: m.trade_count,
            win_count: m.win_count,
            loss_count: m.loss_count,
            breakeven_count: m.breakeven_count,
            net_pnl: m.net_pnl.value ?? 0,
            gross_profit: m.gross_profit.value ?? 0,
            gross_loss: m.gross_loss.value ?? 0,
            long_count: m.long_count,
            long_pnl: m.long_pnl.value ?? 0,
            short_count: m.short_count,
            short_pnl: m.short_pnl.value ?? 0,
            sum_rr: m.sum_rr.value ?? 0,
            rr_count: m.rr_count,
            sum_hold_seconds: m.sum_hold_seconds.value ?? 0,
            hold_count: m.hold_count,
            largest_win: m.largest_win?.value,
            largest_loss: m.largest_loss?.value,
            ingested_revision: revision
        )
    }
}

struct DashboardChartBundleRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "dashboard_chart_bundle"

    var viewer_id: String
    var account_scope_key: String
    var preset_key: String
    var preset_start: String
    var preset_end: String
    var payload_json: Data
    var ingested_revision: Int64

    static func from(
        charts: AnalyticsDashboardChartsPresetV1,
        viewerID: String,
        accountScopeKey: String,
        revision: Int64
    ) throws -> DashboardChartBundleRecord {
        let encoded = try JSONEncoder().encode(charts)
        return DashboardChartBundleRecord(
            viewer_id: viewerID,
            account_scope_key: accountScopeKey,
            preset_key: charts.preset,
            preset_start: charts.start,
            preset_end: charts.end,
            payload_json: encoded,
            ingested_revision: revision
        )
    }

    func decodedCharts() throws -> AnalyticsDashboardChartsPresetV1 {
        try JSONDecoder().decode(AnalyticsDashboardChartsPresetV1.self, from: payload_json)
    }
}
