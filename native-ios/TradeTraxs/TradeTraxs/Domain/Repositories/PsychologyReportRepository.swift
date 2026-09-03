import Foundation

/// Owner-only psychology reports — deterministic generation + session cache.
nonisolated protocol PsychologyReportRepository: Sendable {
    func ensureSnapshot(forceNetwork: Bool) async throws -> PsychologyReportsSnapshot
    func report(for reportID: ReportID, forceNetwork: Bool) async throws -> PsychologyReport
}
