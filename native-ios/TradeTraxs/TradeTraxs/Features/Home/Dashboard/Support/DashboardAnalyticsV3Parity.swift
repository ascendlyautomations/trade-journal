import Foundation

#if DEBUG
enum DashboardAnalyticsV3ParityClassification: String, Sendable {
    case trueMathMismatch = "TRUE_MATH_MISMATCH"
    case expectedDateSemantics = "EXPECTED_DATE_SEMANTICS"
    case legacyPartialHistory = "LEGACY_PARTIAL_HISTORY"
    case v3AccountLookupFailure = "V3_ACCOUNT_LOOKUP_FAILURE"
}

enum DashboardAnalyticsV3Parity {
    struct FieldDelta: Sendable {
        var field: String
        var legacy: String
        var v3: String
        var classification: DashboardAnalyticsV3ParityClassification
    }

    private static let chartDependentMetrics: Set<String> = [
        "current_equity",
        "max_drawdown",
    ]

    static func compare(
        legacy: DashboardChartMetrics.Summary,
        v3: DashboardChartMetrics.Summary,
        preset: DashboardDateRange,
        account: DashboardAccountFilter,
        historyComplete: Bool,
        v3Lookup: DashboardAnalyticsAccountMetricsLookup?,
        chartsAvailability: DashboardAnalyticsChartsAvailability
    ) -> [FieldDelta] {
        if case .accountMetricsMissing = v3Lookup {
            print(
                "[DashboardV3][Parity] preset=\(preset.rawValue) account=\(account) " +
                    "skipped: V3_ACCOUNT_LOOKUP_FAILURE"
            )
            return []
        }

        var deltas: [FieldDelta] = []
        let partialHistoryClass: DashboardAnalyticsV3ParityClassification = historyComplete
            ? .expectedDateSemantics
            : .legacyPartialHistory

        func check(
            _ field: String,
            _ a: Decimal?,
            _ b: Decimal?,
            tolerance: Decimal = 0.01,
            chartDependent: Bool = false
        ) {
            if chartDependent, !chartsAvailability.isLoaded {
                print(
                    "[DashboardV3][Parity] metric=\(field) skipped=charts_not_loaded " +
                        "availability=\(chartsAvailability)"
                )
                return
            }
            let av = a ?? 0
            let bv = b ?? 0
            if abs(av - bv) > tolerance {
                deltas.append(
                    FieldDelta(
                        field: field,
                        legacy: "\(av)",
                        v3: "\(bv)",
                        classification: historyComplete ? .trueMathMismatch : partialHistoryClass
                    )
                )
            }
        }

        check("trade_count", Decimal(legacy.tradeCount), Decimal(v3.tradeCount), tolerance: 0)
        check("net_pnl", legacy.netPnL, v3.netPnL)
        check("win_rate", legacy.winRate, v3.winRate)
        check("profit_factor", legacy.profitFactor, v3.profitFactor)
        check("avg_rr", legacy.averageRR, v3.averageRR)
        check("current_equity", legacy.currentEquity, v3.currentEquity, chartDependent: true)
        check("max_drawdown", legacy.maxDrawdown, v3.maxDrawdown, chartDependent: true)

        if legacy.winCount != v3.winCount || legacy.lossCount != v3.lossCount {
            deltas.append(
                FieldDelta(
                    field: "wins_losses",
                    legacy: "\(legacy.winCount)/\(legacy.lossCount)",
                    v3: "\(v3.winCount)/\(v3.lossCount)",
                    classification: historyComplete ? .trueMathMismatch : partialHistoryClass
                )
            )
        }

        for delta in deltas {
            print(
                "[DashboardV3][Parity] preset=\(preset.rawValue) account=\(account) " +
                    "\(delta.field) legacy=\(delta.legacy) v3=\(delta.v3) class=\(delta.classification.rawValue)"
            )
        }
        return deltas
    }
}
#endif
