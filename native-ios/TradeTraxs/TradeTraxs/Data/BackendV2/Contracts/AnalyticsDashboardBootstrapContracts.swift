import Foundation

nonisolated struct AnalyticsDashboardBootstrapV3: Codable, Sendable, Equatable {
    var meta: BootstrapMetaV1
    var data: DataPayload

    nonisolated struct DataPayload: Codable, Sendable, Equatable {
        var revision: PostgresFlexibleDouble?
        var as_of_et: String
        var payload_kind: String?
        var payout_total: PostgresFlexibleDouble?
        var accounts: [DashboardAccountWireV1]
        /// All-accounts aggregate presets (5 keys). Compact bootstrap is metrics-only; charts load separately.
        var presets: [String: AnalyticsDashboardAggregatePresetV1]?
        /// Per-account metrics-only presets for instant account filter KPIs.
        var account_preset_metrics: [AccountPresetMetrics]?
        /// Legacy bloated shape — read only when `presets` is nil (pre payload-fix servers).
        var scopes: [LegacyScope]?

        var revisionInt: Int64 {
            Int64(revision?.value ?? 0)
        }

        var aggregatePresets: [String: AnalyticsDashboardPresetBundleV1] {
            if let presets, !presets.isEmpty {
                return presets.mapValues { $0.presetBundle() }
            }
            return scopes?.first(where: { $0.account_id == nil })?.presets ?? [:]
        }

        var isCompactPayload: Bool {
            payload_kind == "dashboard_analytics_v3_compact"
        }
    }

    nonisolated struct AccountPresetMetrics: Codable, Sendable, Equatable {
        var account_id: String
        var presets: [String: AnalyticsDashboardMetricsPresetV1]
    }

    nonisolated struct LegacyScope: Codable, Sendable, Equatable {
        var account_id: String?
        var presets: [String: AnalyticsDashboardPresetBundleV1]
    }

    func validateContractVersion() throws {
        try BackendV2Versioning.assertContractVersion(meta.contract_version)
    }
}

nonisolated struct AnalyticsDashboardMetricsPresetV1: Codable, Sendable, Equatable {
    var preset: String
    var start: String
    var end: String
    var metrics: AnalyticsDashboardMetricsWireV1
}

/// Aggregate preset wire shape for ``rpc_v1_analytics_dashboard_bootstrap_v3``.
/// Compact payloads include metrics only; legacy payloads may include chart blocks.
nonisolated struct AnalyticsDashboardAggregatePresetV1: Codable, Sendable, Equatable {
    var preset: String
    var start: String
    var end: String
    var metrics: AnalyticsDashboardMetricsWireV1
    var equity: AnalyticsDashboardEquityWireV1?
    var distributions: AnalyticsDashboardDistributionsWireV1?
    var insights: [AnalyticsDashboardInsightWireV1]?

    func presetBundle() -> AnalyticsDashboardPresetBundleV1 {
        AnalyticsDashboardPresetBundleV1(
            preset: preset,
            start: start,
            end: end,
            metrics: metrics,
            equity: equity ?? Self.emptyEquity,
            distributions: distributions ?? Self.emptyDistributions,
            insights: insights ?? []
        )
    }

    init(
        preset: String,
        start: String,
        end: String,
        metrics: AnalyticsDashboardMetricsWireV1,
        equity: AnalyticsDashboardEquityWireV1? = nil,
        distributions: AnalyticsDashboardDistributionsWireV1? = nil,
        insights: [AnalyticsDashboardInsightWireV1]? = nil
    ) {
        self.preset = preset
        self.start = start
        self.end = end
        self.metrics = metrics
        self.equity = equity
        self.distributions = distributions
        self.insights = insights
    }

    init(full bundle: AnalyticsDashboardPresetBundleV1) {
        preset = bundle.preset
        start = bundle.start
        end = bundle.end
        metrics = bundle.metrics
        equity = bundle.equity
        distributions = bundle.distributions
        insights = bundle.insights
    }

    private static let emptyEquity = AnalyticsDashboardEquityWireV1(
        points: [],
        max_drawdown: PostgresFlexibleDouble(0),
        current_equity: PostgresFlexibleDouble(0)
    )

    private static let emptyDistributions = AnalyticsDashboardDistributionsWireV1(
        sessions: [],
        symbols: [],
        daily: nil,
        streaks: nil,
        weekday_bars: [],
        weekday_heatmap: [],
        hour_bars: [],
        hour_heatmap: [],
        hour_highlights: nil,
        avg_hold_seconds: nil,
        avg_winner_hold_seconds: nil,
        avg_loser_hold_seconds: nil,
        hold_histogram: [],
        hold_extremes: nil,
        long_short: [],
        long_short_detail: nil,
        long_trade_count: 0,
        short_trade_count: 0,
        strategies: nil
    )
}

nonisolated struct AnalyticsDashboardChartsPresetV1: Codable, Sendable, Equatable {
    var preset: String
    var start: String
    var end: String
    var equity: AnalyticsDashboardEquityWireV1
    var distributions: AnalyticsDashboardDistributionsWireV1
    var insights: [AnalyticsDashboardInsightWireV1]
}

nonisolated struct AnalyticsDashboardAccountChartsV3: Codable, Sendable, Equatable {
    var meta: BootstrapMetaV1
    var data: DataPayload

    nonisolated struct DataPayload: Codable, Sendable, Equatable {
        /// Null on all-accounts aggregate charts responses.
        var account_id: String?
        var as_of_et: String
        var presets: [String: AnalyticsDashboardChartsPresetV1]
    }

    func validateContractVersion() throws {
        try BackendV2Versioning.assertContractVersion(meta.contract_version)
    }
}

nonisolated struct AnalyticsDashboardPresetBundleV1: Codable, Sendable, Equatable {
    var preset: String
    var start: String
    var end: String
    var metrics: AnalyticsDashboardMetricsWireV1
    var equity: AnalyticsDashboardEquityWireV1
    var distributions: AnalyticsDashboardDistributionsWireV1
    var insights: [AnalyticsDashboardInsightWireV1]
}

nonisolated struct AnalyticsDashboardMetricsWireV1: Codable, Sendable, Equatable {
    var trade_count: Int
    var win_count: Int
    var loss_count: Int
    var breakeven_count: Int
    var net_pnl: PostgresFlexibleDouble
    var gross_profit: PostgresFlexibleDouble
    var gross_loss: PostgresFlexibleDouble
    var long_count: Int
    var long_pnl: PostgresFlexibleDouble
    var short_count: Int
    var short_pnl: PostgresFlexibleDouble
    var sum_rr: PostgresFlexibleDouble
    var rr_count: Int
    var sum_hold_seconds: PostgresFlexibleDouble
    var hold_count: Int
    var largest_win: PostgresFlexibleDouble?
    var largest_loss: PostgresFlexibleDouble?
}

nonisolated struct AnalyticsDashboardEquityWireV1: Codable, Sendable, Equatable {
    var points: [AnalyticsDashboardEquityPointWireV1]
    var max_drawdown: PostgresFlexibleDouble
    var current_equity: PostgresFlexibleDouble
}

nonisolated struct AnalyticsDashboardEquityPointWireV1: Codable, Sendable, Equatable {
    var t: String
    var v: PostgresFlexibleDouble
    var i: Int?
}

nonisolated struct AnalyticsDashboardDistributionsWireV1: Codable, Sendable, Equatable {
    var sessions: [AnalyticsDashboardSessionWireV1]
    var symbols: [AnalyticsDashboardSymbolWireV1]?
    var daily: AnalyticsDashboardDailyWireV1?
    var streaks: AnalyticsDashboardStreaksWireV1?
    var weekday_bars: [AnalyticsDashboardBarWireV1]
    var weekday_heatmap: [AnalyticsDashboardBarWireV1]
    var hour_bars: [AnalyticsDashboardBarWireV1]
    var hour_heatmap: [AnalyticsDashboardBarWireV1]
    var hour_highlights: AnalyticsDashboardHourHighlightsWireV1?
    var avg_hold_seconds: PostgresFlexibleDouble?
    var avg_winner_hold_seconds: PostgresFlexibleDouble?
    var avg_loser_hold_seconds: PostgresFlexibleDouble?
    var hold_histogram: [AnalyticsDashboardHistogramWireV1]
    var hold_extremes: AnalyticsDashboardHoldExtremesWireV1?
    var long_short: [AnalyticsDashboardBarWireV1]
    var long_short_detail: AnalyticsDashboardLongShortDetailWireV1?
    var long_trade_count: Int
    var short_trade_count: Int
    var strategies: AnalyticsDashboardStrategiesWireV1?

    init(
        sessions: [AnalyticsDashboardSessionWireV1],
        symbols: [AnalyticsDashboardSymbolWireV1]? = nil,
        daily: AnalyticsDashboardDailyWireV1? = nil,
        streaks: AnalyticsDashboardStreaksWireV1? = nil,
        weekday_bars: [AnalyticsDashboardBarWireV1],
        weekday_heatmap: [AnalyticsDashboardBarWireV1],
        hour_bars: [AnalyticsDashboardBarWireV1],
        hour_heatmap: [AnalyticsDashboardBarWireV1],
        hour_highlights: AnalyticsDashboardHourHighlightsWireV1? = nil,
        avg_hold_seconds: PostgresFlexibleDouble? = nil,
        avg_winner_hold_seconds: PostgresFlexibleDouble? = nil,
        avg_loser_hold_seconds: PostgresFlexibleDouble? = nil,
        hold_histogram: [AnalyticsDashboardHistogramWireV1],
        hold_extremes: AnalyticsDashboardHoldExtremesWireV1? = nil,
        long_short: [AnalyticsDashboardBarWireV1],
        long_short_detail: AnalyticsDashboardLongShortDetailWireV1? = nil,
        long_trade_count: Int,
        short_trade_count: Int,
        strategies: AnalyticsDashboardStrategiesWireV1? = nil
    ) {
        self.sessions = sessions
        self.symbols = symbols
        self.daily = daily
        self.streaks = streaks
        self.weekday_bars = weekday_bars
        self.weekday_heatmap = weekday_heatmap
        self.hour_bars = hour_bars
        self.hour_heatmap = hour_heatmap
        self.hour_highlights = hour_highlights
        self.avg_hold_seconds = avg_hold_seconds
        self.avg_winner_hold_seconds = avg_winner_hold_seconds
        self.avg_loser_hold_seconds = avg_loser_hold_seconds
        self.hold_histogram = hold_histogram
        self.hold_extremes = hold_extremes
        self.long_short = long_short
        self.long_short_detail = long_short_detail
        self.long_trade_count = long_trade_count
        self.short_trade_count = short_trade_count
        self.strategies = strategies
    }
}

nonisolated struct AnalyticsDashboardSessionWireV1: Codable, Sendable, Equatable {
    var label: String
    var count: Int
    var pct: PostgresFlexibleDouble
    var trade_count: Int?
    var net_pnl: PostgresFlexibleDouble?
    var wins: Int?
    var losses: Int?
    var win_rate: PostgresFlexibleDouble?
}

nonisolated struct AnalyticsDashboardSymbolWireV1: Codable, Sendable, Equatable {
    var ticker: String
    var trades: Int
    var net_pnl: PostgresFlexibleDouble
    var wins: Int
    var win_rate: PostgresFlexibleDouble?
    var avg_rr: PostgresFlexibleDouble?
}

nonisolated struct AnalyticsDashboardDailyWireV1: Codable, Sendable, Equatable {
    var best_day_pnl: PostgresFlexibleDouble
    var worst_day_pnl: PostgresFlexibleDouble
    var avg_day_pnl: PostgresFlexibleDouble
    var consistency_pct: PostgresFlexibleDouble
    var trading_days: Int
}

nonisolated struct AnalyticsDashboardStreaksWireV1: Codable, Sendable, Equatable {
    var current_streak: Int
    var current_type: String?
    var max_win_streak: Int
    var max_loss_streak: Int
}

nonisolated struct AnalyticsDashboardHourHighlightsWireV1: Codable, Sendable, Equatable {
    var best_hour: Int?
    var worst_hour: Int?
    var best_pnl: PostgresFlexibleDouble?
    var worst_pnl: PostgresFlexibleDouble?
}

nonisolated struct AnalyticsDashboardHoldExtremesWireV1: Codable, Sendable, Equatable {
    var fastest_winner_seconds: PostgresFlexibleDouble?
    var fastest_winner_pnl: PostgresFlexibleDouble?
    var longest_winner_seconds: PostgresFlexibleDouble?
    var longest_winner_pnl: PostgresFlexibleDouble?
    var fastest_loser_seconds: PostgresFlexibleDouble?
    var fastest_loser_pnl: PostgresFlexibleDouble?
    var longest_loser_seconds: PostgresFlexibleDouble?
    var longest_loser_pnl: PostgresFlexibleDouble?
}

nonisolated struct AnalyticsDashboardDirectionSideWireV1: Codable, Sendable, Equatable {
    var trades: Int
    var net_pnl: PostgresFlexibleDouble
    var wins: Int
    var losses: Int
    var win_rate: PostgresFlexibleDouble?
    var profit_factor: PostgresFlexibleDouble?
    var expectancy: PostgresFlexibleDouble?
    var avg_rr: PostgresFlexibleDouble?
    var best_trade: PostgresFlexibleDouble?
    var worst_trade: PostgresFlexibleDouble?
}

nonisolated struct AnalyticsDashboardLongShortDetailWireV1: Codable, Sendable, Equatable {
    var long: AnalyticsDashboardDirectionSideWireV1?
    var short: AnalyticsDashboardDirectionSideWireV1?
}

nonisolated struct AnalyticsDashboardStrategyHighlightWireV1: Codable, Sendable, Equatable {
    var strategy: String
    var trades: Int
    var net_pnl: PostgresFlexibleDouble
    var win_rate: PostgresFlexibleDouble?
}

nonisolated struct AnalyticsDashboardStrategiesWireV1: Codable, Sendable, Equatable {
    var best: AnalyticsDashboardStrategyHighlightWireV1?
    var worst: AnalyticsDashboardStrategyHighlightWireV1?
}

nonisolated struct AnalyticsDashboardBarWireV1: Codable, Sendable, Equatable {
    var label: String
    var value: PostgresFlexibleDouble
}

nonisolated struct AnalyticsDashboardHistogramWireV1: Codable, Sendable, Equatable {
    var label: String
    var count: Int
}

nonisolated struct AnalyticsDashboardInsightWireV1: Codable, Sendable, Equatable {
    var id: String
    var title: String
    var body: String
    var kind: String
}
