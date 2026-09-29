import Foundation

enum FeedbackSubmissionStatus: String, Sendable, CaseIterable, Codable {
    case open
    case planned
    case in_progress
    case resolved
}

enum AdminProductFeedbackQueueFilter: String, Sendable, CaseIterable {
    case unviewed
    case viewed
}

nonisolated enum AdminProductFeedbackTypeFilter: String, Sendable, CaseIterable {
    case all
    case featureRequest
    case improvement
    case bug
    case other

    var feedbackType: ProductFeedbackType? {
        switch self {
        case .all: return nil
        case .featureRequest: return .featureRequest
        case .improvement: return .improvement
        case .bug: return .bug
        case .other: return .other
        }
    }
}

nonisolated enum AdminProductFeedbackStatusFilter: String, Sendable, CaseIterable {
    case all
    case open
    case planned
    case in_progress
    case resolved

    var status: FeedbackSubmissionStatus? {
        switch self {
        case .all: return nil
        case .open: return .open
        case .planned: return .planned
        case .in_progress: return .in_progress
        case .resolved: return .resolved
        }
    }
}

struct AdminProductFeedbackRow: Sendable, Hashable, Identifiable, Codable {
    var id: String
    var userID: ProfileID
    var email: String?
    var rawSubject: String?
    var parsedType: ProductFeedbackType?
    var parsedTitle: String?
    var message: String
    var screenshotURL: String?
    var status: FeedbackSubmissionStatus
    var viewed: Bool
    var adminNotes: String?
    var createdAt: Date?
    var updatedAt: Date?
}

struct AdminProductFeedbackPage: Sendable {
    var rows: [AdminProductFeedbackRow]
    var profiles: [ProfileID: AdminReportProfileSummary]
    var hasMore: Bool
}

struct AdminProductFeedbackSnapshot: Sendable, Hashable, Identifiable, Codable {
    var id: String { row.id }
    var row: AdminProductFeedbackRow
    var submitter: AdminReportProfileSummary?
}

nonisolated struct AdminProductFeedbackListQuery: Sendable {
    static let defaultPageSize = 25
}

struct AdminProductFeedbackReviewUpdate: Sendable {
    var viewed: Bool
    var status: FeedbackSubmissionStatus
    var adminNotes: String?
    var adminUserID: ProfileID
}

nonisolated protocol AdminProductFeedbackRepository: Sendable {
    func fetchFeedback(
        queue: AdminProductFeedbackQueueFilter,
        type: AdminProductFeedbackTypeFilter,
        status: AdminProductFeedbackStatusFilter,
        limit: Int,
        offset: Int
    ) async throws -> AdminProductFeedbackPage

    func updateFeedbackReview(
        feedbackID: String,
        update: AdminProductFeedbackReviewUpdate
    ) async throws
}

enum ProductFeedbackDisplay {
    static func typeLabel(_ type: ProductFeedbackType?) -> String {
        if let type { return type.label }
        return "Unknown"
    }

    static func statusLabel(_ status: FeedbackSubmissionStatus) -> String {
        switch status {
        case .open: return "Open"
        case .planned: return "Planned"
        case .in_progress: return "In progress"
        case .resolved: return "Resolved"
        }
    }

    static func previewText(_ message: String, max: Int) -> String {
        SupportTicketDisplay.previewText(message, max: max)
    }

    static func profileHandle(_ profile: AdminReportProfileSummary?) -> String {
        SupportTicketDisplay.profileHandle(profile)
    }

    static func profileDisplayName(_ profile: AdminReportProfileSummary?) -> String {
        SupportTicketDisplay.profileDisplayName(profile)
    }
}
