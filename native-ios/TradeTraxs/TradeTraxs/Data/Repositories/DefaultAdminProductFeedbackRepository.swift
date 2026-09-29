import Foundation

nonisolated struct DefaultAdminProductFeedbackRepository: AdminProductFeedbackRepository {
    private let supabase: SupabaseInfrastructure

    init(supabase: SupabaseInfrastructure) {
        self.supabase = supabase
    }

    func fetchFeedback(
        queue: AdminProductFeedbackQueueFilter,
        type: AdminProductFeedbackTypeFilter,
        status: AdminProductFeedbackStatusFilter,
        limit: Int,
        offset: Int
    ) async throws -> AdminProductFeedbackPage {
        let pageSize = max(1, min(limit, 50))
        let fetchLimit = pageSize + 1
        var query: [URLQueryItem] = [
            URLQueryItem(
                name: "select",
                value: "id,user_id,email,subject,message,screenshot_url,status,admin_notes,viewed,created_at,updated_at"
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
        }
        if let statusValue = status.status {
            query.append(URLQueryItem(name: "status", value: "eq.\(statusValue.rawValue)"))
        }
        if let feedbackType = type.feedbackType {
            query.append(ProductFeedbackSubjectQuery.orFilter(for: feedbackType))
        }

        let dtos: [ProductFeedbackRowDTO] = try await supabase.database.select(
            ProductFeedbackRowDTO.self,
            from: "feedback_submissions",
            query: query
        )
        let parsed = dtos.compactMap { AdminProductFeedbackParsing.parseRow($0) }
        let hasMore = parsed.count > pageSize
        let pageRows = hasMore ? Array(parsed.prefix(pageSize)) : parsed
        let profiles = try await AdminProductFeedbackHydration.enrichProfiles(
            database: supabase.database,
            userIDs: pageRows.map(\.userID)
        )
        return AdminProductFeedbackPage(rows: pageRows, profiles: profiles, hasMore: hasMore)
    }

    func updateFeedbackReview(
        feedbackID: String,
        update: AdminProductFeedbackReviewUpdate
    ) async throws {
        struct Patch: Encodable {
            var viewed: Bool
            var status: String
            var admin_notes: String?
            var updated_at: String
            var viewed_at: String?
            var viewed_by: String?
        }
        let now = AdminProductFeedbackISO.string(from: Date())
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
            table: "feedback_submissions",
            query: [URLQueryItem(name: "id", value: "eq.\(feedbackID)")]
        )
    }
}

private nonisolated enum AdminProductFeedbackISO {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
