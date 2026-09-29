import Foundation

nonisolated enum AdminBugReportHydration {
    static func enrichProfiles(
        database: any SupabaseDatabaseExecuting,
        userIDs: [ProfileID]
    ) async throws -> [ProfileID: AdminReportProfileSummary] {
        let unique = Array(Set(userIDs))
        guard !unique.isEmpty else { return [:] }
        let query = [
            URLQueryItem(name: "select", value: "id,username,name,avatar_url,is_banned,banned_reason,banned_at"),
            URLQueryItem(name: "id", value: "in.(\(unique.map(\.rawValue).joined(separator: ",")))"),
        ]
        struct Row: Decodable, Sendable {
            var id: String
            var username: String?
            var name: String?
            var avatar_url: String?
            var is_banned: Bool?
            var banned_reason: String?
            var banned_at: String?
        }
        let rows: [Row] = try await database.select(Row.self, from: "profiles", query: query)
        var map: [ProfileID: AdminReportProfileSummary] = [:]
        for row in rows {
            let id = ProfileID(row.id)
            map[id] = AdminReportProfileSummary(
                id: id,
                username: row.username,
                name: row.name,
                avatarURL: row.avatar_url,
                isBanned: row.is_banned == true,
                bannedReason: row.banned_reason,
                bannedAt: row.banned_at.flatMap { AdminBugReportParsing.date(from: $0) }
            )
        }
        return map
    }

    static func snapshot(
        row: AdminBugReportRow,
        profiles: [ProfileID: AdminReportProfileSummary]
    ) -> AdminBugReportSnapshot {
        AdminBugReportSnapshot(row: row, reporter: profiles[row.userID])
    }
}

nonisolated enum AdminBugReportParsing {
    static func date(from string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: string) { return d }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    static func parseRow(_ dto: BugReportRowDTO) -> AdminBugReportRow? {
        guard let severity = BugReportSeverity(rawValue: dto.severity),
              let status = BugReportStatus(rawValue: dto.status)
        else { return nil }
        return AdminBugReportRow(
            id: dto.id,
            userID: ProfileID(dto.user_id),
            title: dto.title,
            description: dto.description,
            screenshotURL: dto.screenshot_url,
            pageURL: dto.page_url,
            browserInfo: dto.browser_info,
            severity: severity,
            status: status,
            createdAt: dto.created_at.flatMap { date(from: $0) },
            resolvedAt: dto.resolved_at.flatMap { date(from: $0) }
        )
    }
}

nonisolated struct BugReportRowDTO: Decodable, Sendable {
    var id: String
    var user_id: String
    var title: String
    var description: String
    var screenshot_url: String?
    var page_url: String?
    var browser_info: String?
    var severity: String
    var status: String
    var created_at: String?
    var resolved_at: String?
}
