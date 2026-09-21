import Foundation

#if DEBUG
nonisolated enum AnalyticsDashboardShadowParity {
    private static let moneyTolerance = 0.01

    static func validateBootstrap(
        viewerID: ProfileID,
        bootstrap: AnalyticsDashboardBootstrapV3,
        localMetrics: [DashboardPresetMetricsRecord],
        localAggregateCharts: [DashboardChartBundleRecord]
    ) -> Bool {
        let started = Date()
        var parity = true
        let revision = bootstrap.data.revisionInt

        let aggregateMetrics = localMetrics.filter {
            $0.scope == AnalyticsLocalSchema.scopeAggregate
        }
        let accountMetrics = localMetrics.filter {
            $0.scope == AnalyticsLocalSchema.scopeAccount
        }

        let expectedAggregate = bootstrap.data.aggregatePresets.count
        if aggregateMetrics.count != expectedAggregate {
            AnalyticsGRDBProbe.logShadowMismatch(
                "aggregate preset count rpc=\(expectedAggregate) local=\(aggregateMetrics.count)"
            )
            parity = false
        }

        var expectedAccountPresets = 0
        for row in bootstrap.data.account_preset_metrics ?? [] {
            expectedAccountPresets += row.presets.count
        }
        if accountMetrics.count != expectedAccountPresets {
            AnalyticsGRDBProbe.logShadowMismatch(
                "account preset count rpc=\(expectedAccountPresets) local=\(accountMetrics.count)"
            )
            parity = false
        }

        for (key, bundle) in bootstrap.data.aggregatePresets {
            guard let local = aggregateMetrics.first(where: { $0.preset_key == key }) else {
                AnalyticsGRDBProbe.logShadowMismatch("missing aggregate preset \(key)")
                parity = false
                continue
            }
            if !metricsMatch(bundle.metrics, local) || local.ingested_revision != revision {
                parity = false
            }
        }

        for row in bootstrap.data.account_preset_metrics ?? [] {
            let accountKey = AnalyticsScopeKeys.accountScopeKey(forQueryAccountID: row.account_id)
            for (key, preset) in row.presets {
                guard let local = accountMetrics.first(where: {
                    $0.preset_key == key && $0.account_scope_key == accountKey
                }) else {
                    AnalyticsGRDBProbe.logShadowMismatch("missing account preset \(row.account_id) \(key)")
                    parity = false
                    continue
                }
                if !metricsMatch(preset.metrics, local) || local.ingested_revision != revision {
                    parity = false
                }
            }
        }

        if localAggregateCharts.count != expectedAggregate {
            AnalyticsGRDBProbe.logShadowMismatch(
                "aggregate chart bundles rpc=\(expectedAggregate) local=\(localAggregateCharts.count)"
            )
            parity = false
        }

        for (key, bundle) in bootstrap.data.aggregatePresets {
            guard let local = localAggregateCharts.first(where: { $0.preset_key == key }) else {
                parity = false
                continue
            }
            if local.ingested_revision != revision {
                AnalyticsGRDBProbe.logShadowMismatch("chart revision preset=\(key)")
                parity = false
            }
            if let charts = try? local.decodedCharts() {
                if charts.equity.points.count != bundle.equity.points.count {
                    AnalyticsGRDBProbe.logShadowMismatch("equity points preset=\(key)")
                    parity = false
                }
            } else {
                parity = false
            }
        }

        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        AnalyticsGRDBProbe.logDashboardShadowParity(
            viewerID: viewerID.rawValue,
            revision: revision,
            aggregatePresets: aggregateMetrics.count,
            accountPresets: accountMetrics.count,
            chartBundles: localAggregateCharts.count,
            parity: parity,
            elapsedMs: elapsed
        )
        return parity
    }

    static func validateAccountCharts(
        viewerID: ProfileID,
        accountID: TradingAccountID,
        revision: Int64,
        response: AnalyticsDashboardAccountChartsV3,
        localBundles: [DashboardChartBundleRecord]
    ) -> Bool {
        let started = Date()
        var parity = true
        let accountKey = AnalyticsScopeKeys.accountScopeKey(forQueryAccountID: accountID.rawValue)

        if localBundles.count != response.data.presets.count {
            AnalyticsGRDBProbe.logShadowMismatch(
                "account chart preset count rpc=\(response.data.presets.count) local=\(localBundles.count)"
            )
            parity = false
        }

        for (key, charts) in response.data.presets {
            guard let local = localBundles.first(where: { $0.preset_key == key }) else {
                AnalyticsGRDBProbe.logShadowMismatch("missing account chart \(key)")
                parity = false
                continue
            }
            if local.account_scope_key != accountKey {
                parity = false
            }
            if local.ingested_revision != revision {
                AnalyticsGRDBProbe.logShadowMismatch(
                    "account chart ingested_revision key=\(key) expected=\(revision) got=\(local.ingested_revision)"
                )
                parity = false
            }
            guard let decoded = try? local.decodedCharts() else {
                parity = false
                continue
            }
            if decoded.equity.points.count != charts.equity.points.count {
                AnalyticsGRDBProbe.logShadowMismatch("equity points account preset=\(key)")
                parity = false
            }
        }

        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        AnalyticsGRDBProbe.logAccountChartsShadowParity(
            viewerID: viewerID.rawValue,
            account: accountKey,
            revision: revision,
            presets: localBundles.count,
            parity: parity,
            elapsedMs: elapsed
        )
        return parity
    }

    private static func metricsMatch(
        _ wire: AnalyticsDashboardMetricsWireV1,
        _ local: DashboardPresetMetricsRecord
    ) -> Bool {
        var ok = true
        if wire.trade_count != local.trade_count { ok = false }
        if abs((wire.net_pnl.value ?? 0) - local.net_pnl) > moneyTolerance { ok = false }
        if abs((wire.gross_profit.value ?? 0) - local.gross_profit) > moneyTolerance { ok = false }
        if abs((wire.gross_loss.value ?? 0) - local.gross_loss) > moneyTolerance { ok = false }
        if !ok {
            AnalyticsGRDBProbe.logShadowMismatch("metric drift trade_count=\(wire.trade_count)")
        }
        return ok
    }
}
#endif
