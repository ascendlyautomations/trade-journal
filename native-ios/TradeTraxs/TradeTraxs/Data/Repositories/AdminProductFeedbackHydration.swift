import Foundation

nonisolated enum AdminProductFeedbackParsing {
    static func date(from string: String) -> Date? {
        AdminBugReportParsing.date(from: string)
    }

    static func parseRow(_ dto: ProductFeedbackRowDTO) -> AdminProductFeedbackRow? {
        guard let status = FeedbackSubmissionStatus(rawValue: dto.status) else { return nil }
        let parsed = ProductFeedbackSubjectCodec.parse(dto.subject)
        return AdminProductFeedbackRow(
            id: dto.id,
            userID: ProfileID(dto.user_id),
            email: dto.email,
            rawSubject: dto.subject,
            parsedType: parsed.type,
            parsedTitle: parsed.title,
            message: dto.message,
            screenshotURL: dto.screenshot_url,
            status: status,
            viewed: dto.viewed ?? false,
            adminNotes: dto.admin_notes,
            createdAt: dto.created_at.flatMap { date(from: $0) },
            updatedAt: dto.updated_at.flatMap { date(from: $0) }
        )
    }
}

nonisolated struct ProductFeedbackRowDTO: Decodable, Sendable {
    var id: String
    var user_id: String
    var email: String?
    var subject: String?
    var message: String
    var screenshot_url: String?
    var status: String
    var admin_notes: String?
    var viewed: Bool?
    var created_at: String?
    var updated_at: String?
}

nonisolated enum AdminProductFeedbackHydration {
    static func enrichProfiles(
        database: any SupabaseDatabaseExecuting,
        userIDs: [ProfileID]
    ) async throws -> [ProfileID: AdminReportProfileSummary] {
        try await AdminBugReportHydration.enrichProfiles(database: database, userIDs: userIDs)
    }

    static func snapshot(
        row: AdminProductFeedbackRow,
        profiles: [ProfileID: AdminReportProfileSummary]
    ) -> AdminProductFeedbackSnapshot {
        AdminProductFeedbackSnapshot(row: row, submitter: profiles[row.userID])
    }
}

nonisolated enum ProductFeedbackSubjectQuery {
    /// PostgREST `or` filter for codec-encoded subjects (exact label or `Label: title`).
    static func orFilter(for type: ProductFeedbackType) -> URLQueryItem {
        let label = type.label
        let titledPrefix = "\(label):"
        return URLQueryItem(
            name: "or",
            value: "(subject.eq.\(postgrestValue(label)),subject.like.\(postgrestValue(titledPrefix))*)"
        )
    }

    private static func postgrestValue(_ raw: String) -> String {
        if raw.contains(" ") || raw.contains(":") {
            return "\"\(raw)\""
        }
        return raw
    }
}
