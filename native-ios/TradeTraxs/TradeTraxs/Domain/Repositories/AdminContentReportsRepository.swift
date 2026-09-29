import Foundation

enum ContentReportStatus: String, Sendable, CaseIterable, Codable {
    case open
    case reviewing
    case resolved
    case dismissed
}

enum AdminContentReportStatusFilter: String, Sendable, CaseIterable {
    case open
    case reviewing
    case resolved
    case dismissed
    case all
}

struct AdminContentReportRow: Sendable, Hashable, Identifiable, Codable {
    var id: String
    var reporterUserID: ProfileID
    var targetType: ContentReportTargetType
    var targetID: String
    var reportedUserID: ProfileID?
    var reason: ContentReportReason
    var details: String?
    var status: ContentReportStatus
    var createdAt: Date?
    var reviewedAt: Date?
    var reviewedBy: ProfileID?

}

nonisolated struct AdminReportProfileSummary: Sendable, Hashable, Codable {
    var id: ProfileID
    var username: String?
    var name: String?
    var avatarURL: String?
    var isBanned: Bool
    var bannedReason: String?
    var bannedAt: Date?
}

nonisolated enum AdminReportOpenDestination: Hashable, Sendable, Codable {
    case trade(TradeID)
    case post(PostID)
    case reel(ReelID)
    case achievement(AchievementID)
    case profile(ProfileID)
    case room(RoomID)
}

nonisolated struct AdminReportTargetPreview: Sendable, Hashable, Codable {
    var targetType: ContentReportTargetType
    var targetID: String
    var headline: String
    var subline: String?
    var ownerUserID: ProfileID?
    var unavailable: Bool
    var openDestination: AdminReportOpenDestination?
}

struct AdminContentReportEnrichment: Sendable {
    var profiles: [ProfileID: AdminReportProfileSummary]
    var targets: [String: AdminReportTargetPreview]
}

struct AdminContentReportPage: Sendable {
    var rows: [AdminContentReportRow]
    var enrichment: AdminContentReportEnrichment
    var hasMore: Bool
}

struct AdminContentReportSnapshot: Sendable, Hashable, Identifiable, Codable {
    var id: String { row.id }
    var row: AdminContentReportRow
    var targetPreview: AdminReportTargetPreview
    var reporter: AdminReportProfileSummary?
    var reportedUser: AdminReportProfileSummary?
}

nonisolated struct AdminContentReportListQuery: Sendable {
    static let defaultPageSize = 25
}

nonisolated protocol AdminContentReportsRepository: Sendable {
    func fetchReports(
        status: AdminContentReportStatusFilter,
        limit: Int,
        offset: Int
    ) async throws -> AdminContentReportPage

    func updateReportStatus(
        reportID: String,
        status: ContentReportStatus,
        reviewerID: ProfileID
    ) async throws
}

nonisolated enum ContentReportDisplay {
    static func statusLabel(_ status: ContentReportStatus) -> String {
        switch status {
        case .open: return "Open"
        case .reviewing: return "Reviewing"
        case .resolved: return "Resolved"
        case .dismissed: return "Dismissed"
        }
    }

    static func targetLabel(_ type: ContentReportTargetType) -> String {
        switch type {
        case .user: return "User"
        case .trade: return "Trade"
        case .post: return "Post"
        case .reel: return "Reel"
        case .story: return "Story"
        case .achievement: return "Achievement"
        case .comment: return "Comment"
        case .directMessage: return "Direct message"
        case .tradeRoom: return "Trade Room"
        case .tradeRoomMessage: return "Trade Room message"
        }
    }

    static func reasonLabel(_ reason: ContentReportReason) -> String {
        reason.title
    }

    static func suggestedBanReason(row: AdminContentReportRow) -> String {
        let reason = reasonLabel(row.reason)
        let details = row.details?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return details.isEmpty ? reason : "\(reason): \(details)"
    }

    static func profileHandle(_ profile: AdminReportProfileSummary?) -> String {
        guard let profile else { return "Unknown user" }
        if let username = profile.username?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty {
            return username.hasPrefix("@") ? username : "@\(username)"
        }
        return String(profile.id.rawValue.prefix(8))
    }

    static func profileDisplayName(_ profile: AdminReportProfileSummary?) -> String {
        guard let profile else { return "Unknown user" }
        if let name = profile.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let username = profile.username?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty {
            return username
        }
        return String(profile.id.rawValue.prefix(8))
    }
}
