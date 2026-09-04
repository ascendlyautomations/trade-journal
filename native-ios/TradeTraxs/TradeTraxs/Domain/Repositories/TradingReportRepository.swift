import Foundation

/// Trading Reports — same deterministic engine as web Dashboard Trading Reports.
///
/// There is no generate/fetch BFF for report bodies. Persistence is the session
/// snapshot (web `tradingReportCache`). Notify uses `POST /api/trading-reports/notify`.
nonisolated protocol TradingReportRepository: Sendable {
    /// Web `ensureTradingReportsLoaded` — load owner trades, generate all periods, cache.
    func ensureSnapshot(forceNetwork: Bool) async throws -> TradingReportsSnapshot

    /// Returns a cached report or generates the full snapshot first.
    func report(for periodKey: TradingReportPeriodKey, forceNetwork: Bool) async throws -> TradingReport

    /// Years with at least one eligible trade for the signed-in owner.
    func availableYears(forceNetwork: Bool) async throws -> [Int]

    /// Yearly performance report for the given calendar year and filters.
    func yearlyReport(
        for year: Int,
        filters: TradingReportFilters,
        forceNetwork: Bool
    ) async throws -> TradingYearlyReport

    /// Calendar month drill-down from a yearly breakdown row.
    func monthReport(
        for ref: TradingReportMonthRef,
        filters: TradingReportFilters,
        forceNetwork: Bool
    ) async throws -> TradingReport
}
