import Foundation

nonisolated struct DefaultAdminSupportTicketsRepository: AdminSupportTicketsRepository {
    private let supabase: SupabaseInfrastructure

    init(supabase: SupabaseInfrastructure) {
        self.supabase = supabase
    }

    func fetchTickets(
        queue: AdminSupportTicketQueueFilter,
        limit: Int,
        offset: Int
    ) async throws -> AdminSupportTicketPage {
        let pageSize = max(1, min(limit, 50))
        let fetchLimit = pageSize + 1
        var query: [URLQueryItem] = [
            URLQueryItem(
                name: "select",
                value: "id,user_id,email,category,subject,message,screenshot_url,status,priority,admin_notes,viewed,created_at,updated_at"
            ),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: String(fetchLimit)),
            URLQueryItem(name: "offset", value: String(max(0, offset))),
        ]
        switch queue {
        case .unviewed:
            query.append(URLQueryItem(name: "viewed", value: "eq.false"))
        case .viewed:
            query.append(URLQueryItem(name: "viewed", value: "eq.true"))
        case .open:
            query.append(URLQueryItem(name: "status", value: "eq.open"))
        case .in_progress:
            query.append(URLQueryItem(name: "status", value: "eq.in_progress"))
        case .resolved:
            query.append(URLQueryItem(name: "status", value: "eq.resolved"))
        }

        let dtos: [SupportTicketRowDTO] = try await supabase.database.select(
            SupportTicketRowDTO.self,
            from: "support_tickets",
            query: query
        )
        let parsed = dtos.compactMap { AdminSupportTicketParsing.parseRow($0) }
        let hasMore = parsed.count > pageSize
        let pageRows = hasMore ? Array(parsed.prefix(pageSize)) : parsed
        let profiles = try await AdminSupportTicketHydration.enrichProfiles(
            database: supabase.database,
            userIDs: pageRows.map(\.userID)
        )
        return AdminSupportTicketPage(rows: pageRows, profiles: profiles, hasMore: hasMore)
    }

    func updateTicketReview(
        ticketID: String,
        update: AdminSupportTicketReviewUpdate
    ) async throws {
        struct Patch: Encodable {
            var viewed: Bool
            var status: String
            var admin_notes: String?
            var updated_at: String
            var viewed_at: String?
            var viewed_by: String?
        }
        let now = AdminSupportTicketISO.string(from: Date())
        let patch = Patch(
            viewed: update.viewed,
            status: update.status.rawValue,
            admin_notes: {
                let trimmed = update.adminNotes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }(),
            updated_at: now,
            viewed_at: update.viewed ? now : nil,
            viewed_by: update.viewed ? update.adminUserID.rawValue : nil
        )
        try await supabase.database.update(
            patch,
            table: "support_tickets",
            query: [URLQueryItem(name: "id", value: "eq.\(ticketID)")]
        )
    }
}

private nonisolated enum AdminSupportTicketISO {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
