import Foundation

/// Normalized scope keys for SQLite (avoids NULL in UNIQUE/PK — Postgres uses NULLS NOT DISTINCT).
nonisolated enum AnalyticsScopeKeys {
    /// Query fetched all accounts (`p_account_id` null).
    static let allAccountsQuery = "*"

    /// Row has no account_id (NULL bucket in `trade_daily_stats`).
    static let nullAccountRow = "__null_account__"

    /// Query fetched all modes (`p_mode` null).
    static let allModesQuery = "*"

    static func accountScopeKey(forRowAccountID raw: String?) -> String {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nullAccountRow
        }
        return DashboardAnalyticsAccountMetricsLookup.normalizedAccountID(trimmed)
    }

    static func accountScopeKey(forQueryAccountID raw: String?) -> String {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return allAccountsQuery
        }
        return DashboardAnalyticsAccountMetricsLookup.normalizedAccountID(trimmed)
    }

    static func modeScopeKey(forQueryMode raw: String?) -> String {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return allModesQuery
        }
        return trimmed.lowercased()
    }
}
