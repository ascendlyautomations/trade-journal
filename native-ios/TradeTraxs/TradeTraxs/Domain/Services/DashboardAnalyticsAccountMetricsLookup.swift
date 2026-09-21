import Foundation

nonisolated enum DashboardAnalyticsAccountMetricsLookup {
    case aggregate(AnalyticsDashboardPresetBundleV1)
    case account(AnalyticsDashboardPresetBundleV1, metricsSource: MetricsSource)
    case accountMetricsMissing(accountID: String, preset: String)

    enum MetricsSource: Sendable, Equatable {
        case accountPresetMetrics
        case aggregateFallbackUsed
    }

    static func normalizedAccountID(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func metricsRow(
        accountID: TradingAccountID,
        in bootstrap: AnalyticsDashboardBootstrapV3
    ) -> AnalyticsDashboardBootstrapV3.AccountPresetMetrics? {
        let target = normalizedAccountID(accountID.rawValue)
        if let row = bootstrap.data.account_preset_metrics?.first(where: {
            normalizedAccountID($0.account_id) == target
        }) {
            return row
        }
        // Fallback: match canonical account list IDs (same UUID, alternate formatting).
        guard let canonical = bootstrap.data.accounts.first(where: {
            normalizedAccountID($0.id) == target
        })?.id else {
            return nil
        }
        let canonicalNorm = normalizedAccountID(canonical)
        return bootstrap.data.account_preset_metrics?.first(where: {
            normalizedAccountID($0.account_id) == canonicalNorm
        })
    }
}
