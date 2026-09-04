import Foundation

/// Session-scoped Performance Report filters — shared between yearly + month drill-down.
@MainActor
final class TradingReportSessionStore {
    static let shared = TradingReportSessionStore()

    var filters = TradingReportFilters()

    private init() {}
}
