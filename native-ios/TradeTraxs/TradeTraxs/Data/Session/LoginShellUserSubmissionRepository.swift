import Foundation

nonisolated struct LoginShellUserSubmissionRepository: UserSubmissionRepository {
    func submitSupportTicket(_ submission: SupportTicketSubmission) async throws {
        _ = submission
        throw UserSubmissionError.notAuthenticated
    }

    func submitFeedback(_ submission: FeedbackSubmission) async throws {
        _ = submission
        throw UserSubmissionError.notAuthenticated
    }

    func submitBugReport(_ submission: BugReportSubmission) async throws {
        _ = submission
        throw UserSubmissionError.notAuthenticated
    }
}
