import Foundation

nonisolated struct DefaultFollowRequestRepository: FollowRequestRepository {
    private let supabase: SupabaseInfrastructure
    private let session: any SessionProviding

    init(supabase: SupabaseInfrastructure, session: any SessionProviding) {
        self.supabase = supabase
        self.session = session
    }

    func pendingRequests() async throws -> [FollowRequest] {
        guard let userID = await session.currentUserID else {
            throw AppError.domain(.permission(.notAuthenticated))
        }
        struct Row: Codable, Sendable {
            var id: String?
            var requester_id: String?
            var created_at: String?
        }
        let rows: [Row] = try await supabase.database.select(
            Row.self,
            from: "follow_requests",
            query: [
                SupabaseQuery.select("id,requester_id,created_at"),
                SupabaseQuery.eq("target_id", userID.rawValue),
                URLQueryItem(name: "status", value: "eq.pending"),
                URLQueryItem(name: "order", value: "created_at.desc"),
            ]
        )
        return rows.compactMap { row in
            guard let id = row.id, let requester = row.requester_id else { return nil }
            return FollowRequest(
                id: FollowRequestID(id),
                requesterProfileID: ProfileID(requester),
                createdAt: ISO8601.date(from: row.created_at) ?? Date()
            )
        }
    }

    func approve(id: FollowRequestID) async throws {
        try await postBFF(path: "/api/follow-requests/approve", requestID: id.rawValue)
    }

    func decline(id: FollowRequestID) async throws {
        try await postBFF(path: "/api/follow-requests/decline", requestID: id.rawValue)
    }

    private func postBFF(path: String, requestID: String) async throws {
        guard let transport = supabase.transport else {
            throw AppError.unknown(message: "Network transport unavailable")
        }
        struct Body: Encodable { var requestId: String }
        let data = try transport.encodeJSON(Body(requestId: requestID))
        let response = try await transport.send(
            host: .bff,
            path: path,
            method: .post,
            body: data,
            requiresAuthentication: true
        )
        guard (200 ... 299).contains(response.statusCode) else {
            throw AppError.unknown(message: "Follow request action failed (\(response.statusCode))")
        }
    }
}
