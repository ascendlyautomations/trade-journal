import Foundation
import UIKit

nonisolated enum UserSubmissionError: Error, Sendable, Equatable {
    case notAuthenticated
    case validation(String)
    case screenshotUpload(String)
    case persistence(String)
}

nonisolated enum SupportTicketCategory: String, CaseIterable, Identifiable, Sendable {
    case bug
    case account
    case billing
    case broker_integration
    case csv_import
    case feature_request
    case general

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bug: return "Bug"
        case .account: return "Account"
        case .billing: return "Billing"
        case .broker_integration: return "Broker Integration"
        case .csv_import: return "CSV Import"
        case .feature_request: return "Feature Request"
        case .general: return "General"
        }
    }
}

nonisolated enum BugReportSeverity: String, CaseIterable, Identifiable, Sendable, Codable {
    case low
    case medium
    case high
    case critical

    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: return "Low, cosmetic or minor"
        case .medium: return "Medium, affects workflow"
        case .high: return "High, major feature broken"
        case .critical: return "Critical, blocker"
        }
    }
}

struct SupportTicketSubmission {
    var category: SupportTicketCategory
    var subject: String
    var message: String
    var screenshot: UIImage?
}

struct FeedbackSubmission {
    var subject: String
    var message: String
    var screenshot: UIImage?
}

struct BugReportSubmission {
    var title: String
    var description: String
    var severity: BugReportSeverity
    var screenshot: UIImage?
}

nonisolated protocol UserSubmissionRepository: Sendable {
    func submitSupportTicket(_ submission: SupportTicketSubmission) async throws
    func submitFeedback(_ submission: FeedbackSubmission) async throws
    func submitBugReport(_ submission: BugReportSubmission) async throws
}
