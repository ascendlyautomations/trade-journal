import Foundation

nonisolated struct DefaultContentReportRepository: ContentReportRepository {
    private let transport: SupabaseTransport

    init(supabase: SupabaseInfrastructure) {
        guard let transport = supabase.transport else {
            preconditionFailure("DefaultContentReportRepository requires Supabase transport")
        }
        self.transport = transport
    }

    init(transport: SupabaseTransport) {
        self.transport = transport
    }

    func submit(
        target: ContentReportTarget,
        reason: ContentReportReason,
        details: String?
    ) async throws -> ContentReportSubmissionResult {
        struct Body: Encodable {
            var targetType: String
            var targetId: String
            var reportedUserId: String?
            var reason: String
            var details: String?
        }

        struct Response: Decodable {
            var ok: Bool?
            var duplicate: Bool?
            var id: String?
            var error: String?
            var message: String?
        }

        let trimmedDetails = details?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let body = Body(
            targetType: target.type.rawValue,
            targetId: target.targetID,
            reportedUserId: target.reportedUserID?.rawValue,
            reason: reason.rawValue,
            details: trimmedDetails?.isEmpty == false ? trimmedDetails : nil
        )

        let data = try transport.encodeJSON(body)
        let response = try await transport.send(
            host: .bff,
            path: "/api/content-reports",
            method: .post,
            body: data,
            requiresAuthentication: true
        )

        let decoded = try? JSONDecoder().decode(Response.self, from: response.data)

        switch response.statusCode {
        case 200 ... 299:
            if decoded?.ok == true {
                return ContentReportSubmissionResult(
                    reportID: decoded?.id,
                    wasDuplicate: decoded?.duplicate == true
                )
            }
            throw ContentReportSubmissionError.serverMessage(
                decoded?.error ?? "Report submission failed."
            )
        case 401:
            throw ContentReportSubmissionError.notAuthenticated
        case 409:
            throw ContentReportSubmissionError.duplicate
        default:
            throw ContentReportSubmissionError.serverMessage(
                decoded?.error ?? decoded?.message ?? "Report submission failed."
            )
        }
    }
}
