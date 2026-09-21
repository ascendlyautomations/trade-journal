import Foundation

extension AnalyticsDailyStatRecord {
    func toWireRow() -> AnalyticsDailyStatRowV1 {
        let accountID: String? = {
            if account_scope_key == AnalyticsScopeKeys.nullAccountRow { return nil }
            if account_scope_key == AnalyticsScopeKeys.allAccountsQuery { return nil }
            return account_scope_key
        }()
        return AnalyticsDailyStatRowV1(
            calendar_day: calendar_day,
            account_id: accountID,
            mode_effective: mode_effective,
            trade_count: trade_count,
            win_count: win_count,
            loss_count: loss_count,
            breakeven_count: breakeven_count,
            net_pnl: PostgresFlexibleDouble(net_pnl),
            gross_profit: PostgresFlexibleDouble(gross_profit),
            gross_loss: PostgresFlexibleDouble(gross_loss),
            long_count: long_count,
            long_pnl: PostgresFlexibleDouble(long_pnl),
            short_count: short_count,
            short_pnl: PostgresFlexibleDouble(short_pnl),
            sum_rr: PostgresFlexibleDouble(sum_rr),
            rr_count: rr_count,
            sum_hold_seconds: PostgresFlexibleDouble(sum_hold_seconds),
            hold_count: hold_count,
            largest_win: largest_win.map { PostgresFlexibleDouble($0) },
            largest_loss: largest_loss.map { PostgresFlexibleDouble($0) }
        )
    }
}

extension DashboardPresetMetricsRecord {
    func toMetricsPreset() -> AnalyticsDashboardMetricsPresetV1 {
        AnalyticsDashboardMetricsPresetV1(
            preset: preset_key,
            start: preset_start,
            end: preset_end,
            metrics: AnalyticsDashboardMetricsWireV1(
                trade_count: trade_count,
                win_count: win_count,
                loss_count: loss_count,
                breakeven_count: breakeven_count,
                net_pnl: PostgresFlexibleDouble(net_pnl),
                gross_profit: PostgresFlexibleDouble(gross_profit),
                gross_loss: PostgresFlexibleDouble(gross_loss),
                long_count: long_count,
                long_pnl: PostgresFlexibleDouble(long_pnl),
                short_count: short_count,
                short_pnl: PostgresFlexibleDouble(short_pnl),
                sum_rr: PostgresFlexibleDouble(sum_rr),
                rr_count: rr_count,
                sum_hold_seconds: PostgresFlexibleDouble(sum_hold_seconds),
                hold_count: hold_count,
                largest_win: largest_win.map { PostgresFlexibleDouble($0) },
                largest_loss: largest_loss.map { PostgresFlexibleDouble($0) }
            )
        )
    }
}
