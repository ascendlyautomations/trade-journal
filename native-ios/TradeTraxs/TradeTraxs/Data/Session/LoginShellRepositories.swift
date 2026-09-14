import Foundation

/// Logged-out launch shell — satisfies ``ContentReportRepository`` without Supabase transport.
///
/// Production reporting remains ``DefaultContentReportRepository`` after deferred bootstrap.
nonisolated struct LoginShellContentReportRepository: ContentReportRepository {
    func submit(
        target: ContentReportTarget,
        reason: ContentReportReason,
        details: String?
    ) async throws -> ContentReportSubmissionResult {
        _ = (target, reason, details)
        throw AppError.authentication(.notConfigured)
    }
}
