import Foundation

/// PostgREST / Postgres failures that should not trigger chart overlay retry loops.
nonisolated enum DashboardAnalyticsChartsFailurePolicy {
    static func shouldNotRetry(_ error: Error) -> Bool {
        let pieces = [
            String(describing: error),
            (error as NSError).localizedDescription,
            (error as NSError).userInfo[NSLocalizedDescriptionKey] as? String ?? "",
        ]
        let text = pieces.joined(separator: " ").lowercased()
        if text.contains("42501") { return true }
        if text.contains("permission denied") { return true }
        if text.contains("not_authenticated") { return true }
        return false
    }
}
