import Foundation

/// Explicit local analytical read availability (shadow read layer — not UI-authoritative).
nonisolated enum AnalyticsLocalReadState: Equatable, Sendable, CustomStringConvertible {
    /// Coverage and row revision requirements satisfied; zero rows is still available.
    case available
    /// Persisted data exists but not at the required server revision.
    case stale(foundRevision: Int64?)
    /// Required range or snapshot is only partly present at the required revision.
    case partial
    /// No synchronized material for the requested scope.
    case missing

    var description: String {
        switch self {
        case .available: return "available"
        case .stale(let foundRevision):
            if let foundRevision { return "stale(found=\(foundRevision))" }
            return "stale"
        case .partial: return "partial"
        case .missing: return "missing"
        }
    }
}

nonisolated enum AnalyticsLocalDashboardPolicy {
    static let aggregatePresetKeys: [String] = ["d7", "d30", "d90", "ytd", "all"]
}

/// Presentation-oriented Calendar read (no server revision required upfront).
struct AnalyticsCalendarPresentationReadResult: Sendable, Equatable {
    var state: AnalyticsLocalReadState
    var effectiveRevision: Int64?
    var startDate: String
    var endDate: String
    var accountScope: String
    var modeScope: String
    var wireRows: [AnalyticsDailyStatRowV1]
    /// Full range covered at `effectiveRevision` — render locally (available or stale last-known).
    var canRenderLocally: Bool
}

struct AnalyticsCalendarRangeReadResult: Sendable, Equatable {
    var state: AnalyticsLocalReadState
    var requiredRevision: Int64
    var startDate: String
    var endDate: String
    var accountScope: String
    var modeScope: String
    /// Daily stat rows when `state == .available` (may be empty).
    var dailyRows: [AnalyticsDailyStatRecord]
    var wireRows: [AnalyticsDailyStatRowV1]
    var coverageRevision: Int64?
}

struct AnalyticsDashboardPresentationReadResult: Sendable, Equatable {
    var state: AnalyticsLocalReadState
    var effectiveRevision: Int64?
    var snapshot: AnalyticsLocalDashboardV3Snapshot?
    var canRenderLocally: Bool
    var elapsedMs: Int
}

struct AnalyticsDashboardSnapshotReadResult: Sendable, Equatable {
    var state: AnalyticsLocalReadState
    var requiredRevision: Int64
    var snapshot: AnalyticsLocalDashboardV3Snapshot?
}

/// GRDB materialization of Dashboard V3 bootstrap (aggregate metrics + aggregate charts only).
struct AnalyticsLocalDashboardV3Snapshot: Sendable, Equatable {
    var revision: Int64
    var asOfET: String
    var aggregatePresets: [String: AnalyticsDashboardPresetBundleV1]
    var accountPresetMetrics: [AnalyticsDashboardBootstrapV3.AccountPresetMetrics]
}

struct AnalyticsDashboardAccountChartsReadResult: Sendable, Equatable {
    var state: AnalyticsLocalReadState
    var requiredRevision: Int64
    var accountScopeKey: String
    var presets: [String: AnalyticsDashboardChartsPresetV1]
}
