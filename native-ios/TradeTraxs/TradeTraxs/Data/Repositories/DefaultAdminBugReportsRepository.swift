import Foundation

nonisolated struct DefaultAdminBugReportsRepository: AdminBugReportsRepository {
    private let supabase: SupabaseInfrastructure

    init(supabase: SupabaseInfrastructure) {
        self.supabase = supabase
    }

    func fetchReports(
        status: AdminBugReportStatusFilter,
        severity: AdminBugReportSeverityFilter,
        limit: Int,
        offset: Int
    ) async throws -> AdminBugReportPage {
        let pageSize = max(1, min(limit, 50))
        let fetchLimit = pageSize + 1
        var query: [URLQueryItem] = [
            URLQueryItem(
                name: "select",
                value: "id,user_id,title,description,screenshot_url,page_url,browser_info,severity,status,created_at,resolved_at"
            ),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: String(fetchLimit)),
            URLQueryItem(name: "offset", value: String(max(0, offset))),
        ]
        if status != .all {
            query.append(URLQueryItem(name: "status", value: "eq.\(status.rawValue)"))
        }
        if severity != .all {
            query.append(URLQueryItem(name: "severity", value: "eq.\(severity.rawValue)"))
        }

        let dtos: [BugReportRowDTO] = try await supabase.database.select(
            BugReportRowDTO.self,
            from: "bug_reports",
            query: query
        )
        let parsed = dtos.compactMap { AdminBugReportParsing.parseRow($0) }
        let hasMore = parsed.count > pageSize
        let pageRows = hasMore ? Array(parsed.prefix(pageSize)) : parsed
        let profiles = try await AdminBugReportHydration.enrichProfiles(
            database: supabase.database,
            userIDs: pageRows.map(\.userID)
        )
        return AdminBugReportPage(rows: pageRows, profiles: profiles, hasMore: hasMore)
    }

    func updateReportStatus(
        reportID: String,
        status: BugReportStatus,
        previousStatus: BugReportStatus,
        existingResolvedAt: Date?
    ) async throws {
        struct Patch: Encodable {
            var status: String
            var resolved_at: String?
        }
        let resolved = status == .resolved
        let resolvedAt: String?
        if resolved {
            if previousStatus == .resolved, let existingResolvedAt {
                resolvedAt = AdminBugReportISO.string(from: existingResolvedAt)
            } else {
                resolvedAt = AdminBugReportISO.string(from: Date())
            }
        } else {
            resolvedAt = nil
        }
        let patch = Patch(status: status.rawValue, resolved_at: resolvedAt)
        try await supabase.database.update(
            patch,
            table: "bug_reports",
            query: [URLQueryItem(name: "id", value: "eq.\(reportID)")]
        )
    }
}

private nonisolated enum AdminBugReportISO {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
