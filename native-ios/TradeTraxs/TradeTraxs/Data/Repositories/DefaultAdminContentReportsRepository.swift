import Foundation

nonisolated struct DefaultAdminContentReportsRepository: AdminContentReportsRepository {
    private let supabase: SupabaseInfrastructure

    init(supabase: SupabaseInfrastructure) {
        self.supabase = supabase
    }

    func fetchReports(
        status: AdminContentReportStatusFilter,
        limit: Int,
        offset: Int
    ) async throws -> AdminContentReportPage {
        let pageSize = max(1, min(limit, 50))
        let fetchLimit = pageSize + 1
        var query: [URLQueryItem] = [
            URLQueryItem(
                name: "select",
                value: "id,reporter_user_id,target_type,target_id,reported_user_id,reason,details,status,created_at,reviewed_at,reviewed_by"
            ),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: String(fetchLimit)),
            URLQueryItem(name: "offset", value: String(max(0, offset))),
        ]
        if status != .all {
            query.append(URLQueryItem(name: "status", value: "eq.\(status.rawValue)"))
        }

        let dtos: [ContentReportRowDTO] = try await supabase.database.select(
            ContentReportRowDTO.self,
            from: "content_reports",
            query: query
        )
        let parsed = dtos.compactMap { AdminContentReportParsing.parseRow($0) }
        let hasMore = parsed.count > pageSize
        let pageRows = hasMore ? Array(parsed.prefix(pageSize)) : parsed
        let enrichment = try await AdminContentReportHydration.enrich(
            database: supabase.database,
            rows: pageRows
        )
        return AdminContentReportPage(rows: pageRows, enrichment: enrichment, hasMore: hasMore)
    }

    func updateReportStatus(
        reportID: String,
        status: ContentReportStatus,
        reviewerID: ProfileID
    ) async throws {
        struct Patch: Encodable {
            var status: String
            var reviewed_at: String
            var reviewed_by: String
        }
        let patch = Patch(
            status: status.rawValue,
            reviewed_at: AdminContentReportParsingISO.string(from: Date()),
            reviewed_by: reviewerID.rawValue
        )
        try await supabase.database.update(
            patch,
            table: "content_reports",
            query: [URLQueryItem(name: "id", value: "eq.\(reportID)")]
        )
    }
}

private nonisolated enum AdminContentReportParsingISO {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
