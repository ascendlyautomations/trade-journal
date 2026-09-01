import Foundation

/// Maps profile `achievements.id` → feed/web `achievement_posts.id` for likes/comments.
actor AchievementInteractionPostIDResolver {
    static let shared = AchievementInteractionPostIDResolver()

    private var cache: [String: String] = [:]

    func postID(
        for postOrAchievementID: String,
        database: any SupabaseDatabaseExecuting
    ) async throws -> String {
        let key = postOrAchievementID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return postOrAchievementID }
        if let cached = cache[key] { return cached }

        let resolved = try await lookupPostID(for: key, database: database)
        cache[key] = resolved
        cache[resolved] = resolved
        return resolved
    }

    func resetCache() {
        cache.removeAll()
    }

    private struct PostRow: Decodable, Sendable {
        var id: String?
    }

    private func lookupPostID(
        for key: String,
        database: any SupabaseDatabaseExecuting
    ) async throws -> String {
        // Feed / deep links already pass `achievement_posts.id`.
        if let row: PostRow = try? await database.selectOne(
            PostRow.self,
            from: "achievement_posts",
            query: [
                SupabaseQuery.select("id"),
                SupabaseQuery.eq("id", key),
            ]
        ), row.id != nil {
            return key
        }

        // Profile achievements list/detail uses `achievements.id`.
        if let row: PostRow = try? await database.selectOne(
            PostRow.self,
            from: "achievement_posts",
            query: [
                SupabaseQuery.select("id"),
                SupabaseQuery.eq("achievement_id", key),
            ]
        ),
            let postID = row.id?.trimmingCharacters(in: .whitespacesAndNewlines),
            !postID.isEmpty {
            return postID
        }

        return key
    }
}
