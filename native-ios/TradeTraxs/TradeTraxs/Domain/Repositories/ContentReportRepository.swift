import Foundation

nonisolated protocol ContentReportRepository: Sendable {
    func submit(
        target: ContentReportTarget,
        reason: ContentReportReason,
        details: String?
    ) async throws -> ContentReportSubmissionResult
}

nonisolated struct ContentReportSubmissionResult: Sendable, Equatable {
    var reportID: String?
    var wasDuplicate: Bool
}
