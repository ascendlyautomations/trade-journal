import Foundation

nonisolated enum AnalyticsLocalSchema {
    static let localSchemaVersion = 3

    static let domainCalendar = "calendar"
    static let domainDashboardBootstrap = "dashboard_bootstrap"
    static let domainDashboardAccountCharts = "dashboard_account_charts"
    static let domainDashboardAggregateCharts = "dashboard_aggregate_charts"
    static let domainProfileAnalytics = "profile_analytics"

    static let profileAnalyticsContractVersion = "v2"

    static let scopeAggregate = "aggregate"
    static let scopeAccount = "account"

    static let createSyncState = """
        CREATE TABLE IF NOT EXISTS analytics_sync_state (
            viewer_id TEXT PRIMARY KEY NOT NULL,
            server_revision INTEGER NOT NULL,
            updated_at TEXT NOT NULL,
            local_schema_version INTEGER NOT NULL
        );
        """

    static let createDailyStat = """
        CREATE TABLE IF NOT EXISTS analytics_daily_stat (
            viewer_id TEXT NOT NULL,
            calendar_day TEXT NOT NULL,
            mode_effective TEXT NOT NULL,
            account_scope_key TEXT NOT NULL,
            trade_count INTEGER NOT NULL,
            win_count INTEGER NOT NULL,
            loss_count INTEGER NOT NULL,
            breakeven_count INTEGER NOT NULL,
            net_pnl REAL NOT NULL,
            gross_profit REAL NOT NULL,
            gross_loss REAL NOT NULL,
            long_count INTEGER NOT NULL DEFAULT 0,
            long_pnl REAL NOT NULL DEFAULT 0,
            short_count INTEGER NOT NULL DEFAULT 0,
            short_pnl REAL NOT NULL DEFAULT 0,
            sum_rr REAL NOT NULL DEFAULT 0,
            rr_count INTEGER NOT NULL DEFAULT 0,
            sum_hold_seconds REAL NOT NULL DEFAULT 0,
            hold_count INTEGER NOT NULL DEFAULT 0,
            largest_win REAL,
            largest_loss REAL,
            ingested_revision INTEGER NOT NULL,
            PRIMARY KEY (viewer_id, calendar_day, mode_effective, account_scope_key)
        );
        """

    static let createDailyStatDayIndex = """
        CREATE INDEX IF NOT EXISTS analytics_daily_stat_viewer_day_idx
        ON analytics_daily_stat (viewer_id, calendar_day);
        """

    static let createCoverage = """
        CREATE TABLE IF NOT EXISTS analytics_range_coverage (
            viewer_id TEXT NOT NULL,
            domain TEXT NOT NULL,
            account_scope TEXT NOT NULL,
            mode_scope TEXT NOT NULL,
            start_date TEXT NOT NULL,
            end_date TEXT NOT NULL,
            server_revision INTEGER NOT NULL,
            fetched_at TEXT NOT NULL,
            PRIMARY KEY (viewer_id, domain, account_scope, mode_scope, start_date, end_date)
        );
        """

    static let createDashboardPresetMetrics = """
        CREATE TABLE IF NOT EXISTS dashboard_preset_metrics (
            viewer_id TEXT NOT NULL,
            scope TEXT NOT NULL,
            account_scope_key TEXT NOT NULL,
            preset_key TEXT NOT NULL,
            preset_start TEXT NOT NULL,
            preset_end TEXT NOT NULL,
            as_of_et TEXT NOT NULL,
            trade_count INTEGER NOT NULL,
            win_count INTEGER NOT NULL,
            loss_count INTEGER NOT NULL,
            breakeven_count INTEGER NOT NULL,
            net_pnl REAL NOT NULL,
            gross_profit REAL NOT NULL,
            gross_loss REAL NOT NULL,
            long_count INTEGER NOT NULL,
            long_pnl REAL NOT NULL,
            short_count INTEGER NOT NULL,
            short_pnl REAL NOT NULL,
            sum_rr REAL NOT NULL,
            rr_count INTEGER NOT NULL,
            sum_hold_seconds REAL NOT NULL,
            hold_count INTEGER NOT NULL,
            largest_win REAL,
            largest_loss REAL,
            ingested_revision INTEGER NOT NULL,
            PRIMARY KEY (viewer_id, scope, account_scope_key, preset_key)
        );
        """

    static let createDashboardChartBundle = """
        CREATE TABLE IF NOT EXISTS dashboard_chart_bundle (
            viewer_id TEXT NOT NULL,
            account_scope_key TEXT NOT NULL,
            preset_key TEXT NOT NULL,
            preset_start TEXT NOT NULL,
            preset_end TEXT NOT NULL,
            payload_json BLOB NOT NULL,
            ingested_revision INTEGER NOT NULL,
            PRIMARY KEY (viewer_id, account_scope_key, preset_key)
        );
        """

    static let createDashboardPresetIndex = """
        CREATE INDEX IF NOT EXISTS dashboard_preset_metrics_viewer_idx
        ON dashboard_preset_metrics (viewer_id);
        """

    static let createDashboardChartIndex = """
        CREATE INDEX IF NOT EXISTS dashboard_chart_bundle_viewer_idx
        ON dashboard_chart_bundle (viewer_id, account_scope_key);
        """

    /// Profile Statistics V2 — keyed by viewer + subject + contract + visibility (not owner sync state).
    static let createProfileAnalyticsSnapshot = """
        CREATE TABLE IF NOT EXISTS profile_analytics_snapshot (
            viewer_id TEXT NOT NULL,
            subject_profile_id TEXT NOT NULL,
            contract_version TEXT NOT NULL,
            visibility_identity TEXT NOT NULL,
            public_revision INTEGER NOT NULL,
            fetched_at TEXT NOT NULL,
            modes_payload_json BLOB NOT NULL,
            PRIMARY KEY (viewer_id, subject_profile_id, contract_version, visibility_identity)
        );
        """

    static let createProfileAnalyticsSnapshotIndex = """
        CREATE INDEX IF NOT EXISTS profile_analytics_snapshot_viewer_subject_idx
        ON profile_analytics_snapshot (viewer_id, subject_profile_id);
        """
}
