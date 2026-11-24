import Foundation

/// Owner-only psychology reports, deterministic generation + session cache.
nonisolated protocol PsychologyReportRepository: Sendable {
    func ensureSnapshot(forceNetwork: Bool) async throws -> PsychologyReportsSnapshot
    func report(for reportID: ReportID, forceNetwork: Bool) async throws -> PsychologyReport
    /// Regenerates one report for the given period ref (thematic date-range changes).
    func generateReport(periodRef: PsychologyReportPeriodRef, forceNetwork: Bool) async throws -> PsychologyReport
}
