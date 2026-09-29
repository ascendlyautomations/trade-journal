import Foundation

enum BugReportStatus: String, Sendable, CaseIterable, Codable {
    case open
    case in_progress
    case resolved
}

enum AdminBugReportStatusFilter: String, Sendable, CaseIterable {
    case open
    case in_progress
    case resolved
    case all
}

enum AdminBugReportSeverityFilter: String, Sendable, CaseIterable {
    case low
    case medium
    case high
    case critical
    case all
}

struct AdminBugReportRow: Sendable, Hashable, Identifiable, Codable {
    var id: String
    var userID: ProfileID
    var title: String
    var description: String
    var screenshotURL: String?
    var pageURL: String?
    var browserInfo: String?
    var severity: BugReportSeverity
    var status: BugReportStatus
    var createdAt: Date?
    var resolvedAt: Date?
}

struct AdminBugReportPage: Sendable {
    var rows: [AdminBugReportRow]
    var profiles: [ProfileID: AdminReportProfileSummary]
    var hasMore: Bool
}

struct AdminBugReportSnapshot: Sendable, Hashable, Identifiable, Codable {
    var id: String { row.id }
    var row: AdminBugReportRow
    var reporter: AdminReportProfileSummary?
}

nonisolated struct AdminBugReportListQuery: Sendable {
    static let defaultPageSize = 25
}

nonisolated protocol AdminBugReportsRepository: Sendable {
    func fetchReports(
        status: AdminBugReportStatusFilter,
        severity: AdminBugReportSeverityFilter,
        limit: Int,
        offset: Int
    ) async throws -> AdminBugReportPage

    func updateReportStatus(
        reportID: String,
        status: BugReportStatus,
        previousStatus: BugReportStatus,
        existingResolvedAt: Date?
    ) async throws
}

enum BugReportDisplay {
    static func statusLabel(_ status: BugReportStatus) -> String {
        switch status {
        case .open: return "Open"
        case .in_progress: return "In progress"
        case .resolved: return "Resolved"
        }
    }

    static func severityLabel(_ severity: BugReportSeverity) -> String {
        switch severity {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }

    static func severityShortLabel(_ severity: BugReportSeverity) -> String {
        severityLabel(severity)
    }

    static func profileHandle(_ profile: AdminReportProfileSummary?) -> String {
        ContentReportDisplay.profileHandle(profile)
    }

    static func profileDisplayName(_ profile: AdminReportProfileSummary?) -> String {
        ContentReportDisplay.profileDisplayName(profile)
    }

    static func previewText(_ text: String, max: Int = 120) -> String {
        let trimmed = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "—" }
        if trimmed.count <= max { return trimmed }
        return String(trimmed.prefix(max)) + "…"
    }

    static func environmentContextLabel(pageURL: String?) -> String {
        let url = pageURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if url.lowercased().hasPrefix("ios://") { return "App route" }
        if url.isEmpty { return "Page URL" }
        return "Page URL"
    }

    static func environmentClientLabel(browserInfo: String?) -> String {
        let info = browserInfo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if info.lowercased().contains("tradetraxs") || info.lowercased().contains("iphone") {
            return "App / device"
        }
        if info.isEmpty { return "Browser" }
        return "Browser"
    }
}
