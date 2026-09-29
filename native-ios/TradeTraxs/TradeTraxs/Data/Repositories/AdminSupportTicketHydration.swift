import Foundation

nonisolated enum AdminSupportTicketParsing {
    static func date(from string: String) -> Date? {
        AdminBugReportParsing.date(from: string)
    }

    static func parseRow(_ dto: SupportTicketRowDTO) -> AdminSupportTicketRow? {
        guard let status = SupportTicketStatus(rawValue: dto.status) else { return nil }
        return AdminSupportTicketRow(
            id: dto.id,
            userID: ProfileID(dto.user_id),
            email: dto.email,
            category: dto.category,
            subject: dto.subject,
            message: dto.message,
            screenshotURL: dto.screenshot_url,
            status: status,
            priority: dto.priority ?? "normal",
            viewed: dto.viewed ?? false,
            adminNotes: dto.admin_notes,
            createdAt: dto.created_at.flatMap { date(from: $0) },
            updatedAt: dto.updated_at.flatMap { date(from: $0) }
        )
    }
}

nonisolated struct SupportTicketRowDTO: Decodable, Sendable {
    var id: String
    var user_id: String
    var email: String?
    var category: String
    var subject: String
    var message: String
    var screenshot_url: String?
    var status: String
    var priority: String?
    var admin_notes: String?
    var viewed: Bool?
    var created_at: String?
    var updated_at: String?
}

nonisolated enum AdminSupportTicketHydration {
    static func enrichProfiles(
        database: any SupabaseDatabaseExecuting,
        userIDs: [ProfileID]
    ) async throws -> [ProfileID: AdminReportProfileSummary] {
        try await AdminBugReportHydration.enrichProfiles(database: database, userIDs: userIDs)
    }

    static func snapshot(
        row: AdminSupportTicketRow,
        profiles: [ProfileID: AdminReportProfileSummary]
    ) -> AdminSupportTicketSnapshot {
        AdminSupportTicketSnapshot(row: row, submitter: profiles[row.userID])
    }
}
