import Foundation

/// A single public metric shown in the Profile header statistics row.
///
/// Append new cases by constructing additional metrics — the row lays them out
/// without requiring a header redesign.
struct ProfileHeaderMetric: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    /// Display string. Use `"—"` when a metric is not yet available from cache.
    let value: String

    static let placeholderValue = "—"
}
