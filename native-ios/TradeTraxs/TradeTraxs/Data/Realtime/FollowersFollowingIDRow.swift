import Foundation

/// Supabase `followers` row fragment for relationship repair fetches.
nonisolated struct FollowersFollowingIDRow: Codable, Sendable {
    var following_id: String?
}
