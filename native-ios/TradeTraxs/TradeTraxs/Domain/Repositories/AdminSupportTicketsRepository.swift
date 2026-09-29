import Foundation

enum SupportTicketStatus: String, Sendable, CaseIterable, Codable {
    case open
    case in_progress
    case resolved
}

enum AdminSupportTicketQueueFilter: String, Sendable, CaseIterable {
    case unviewed
    case viewed
    case open
    case in_progress
    case resolved
}

struct AdminSupportTicketRow: Sendable, Hashable, Identifiable, Codable {
    var id: String
    var userID: ProfileID
    var email: String?
    var category: String
    var subject: String
    var message: String
    var screenshotURL: String?
    var status: SupportTicketStatus
    var priority: String
    var viewed: Bool
    var adminNotes: String?
    var createdAt: Date?
    var updatedAt: Date?
}

struct AdminSupportTicketPage: Sendable {
    var rows: [AdminSupportTicketRow]
    var profiles: [ProfileID: AdminReportProfileSummary]
    var hasMore: Bool
}

struct AdminSupportTicketSnapshot: Sendable, Hashable, Identifiable, Codable {
    var id: String { row.id }
    var row: AdminSupportTicketRow
    var submitter: AdminReportProfileSummary?
}

nonisolated struct AdminSupportTicketListQuery: Sendable {
    static let defaultPageSize = 25
}

struct AdminSupportTicketReviewUpdate: Sendable {
    var viewed: Bool
    var status: SupportTicketStatus
    var adminNotes: String?
    var adminUserID: ProfileID
}

nonisolated protocol AdminSupportTicketsRepository: Sendable {
    func fetchTickets(
        queue: AdminSupportTicketQueueFilter,
        limit: Int,
        offset: Int
    ) async throws -> AdminSupportTicketPage

    func updateTicketReview(
        ticketID: String,
        update: AdminSupportTicketReviewUpdate
    ) async throws
}

enum SupportTicketDisplay {
    static func categoryLabel(_ raw: String) -> String {
        if let known = SupportTicketCategory(rawValue: raw) {
            return known.label
        }
        switch raw {
        case "broker_integration": return "Broker Integration"
        default:
            return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func statusLabel(_ status: SupportTicketStatus) -> String {
        switch status {
        case .open: return "Open"
        case .in_progress: return "In progress"
        case .resolved: return "Resolved"
        }
    }

    static func previewText(_ message: String, max: Int) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "—" }
        let collapsed = trimmed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if collapsed.count <= max { return collapsed }
        return String(collapsed.prefix(max)) + "…"
    }

    static func profileHandle(_ profile: AdminReportProfileSummary?) -> String {
        if let username = profile?.username?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty {
            return username.hasPrefix("@") ? username : "@\(username)"
        }
        return "Unknown user"
    }

    static func profileDisplayName(_ profile: AdminReportProfileSummary?) -> String {
        if let name = profile?.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return profileHandle(profile)
    }
}
