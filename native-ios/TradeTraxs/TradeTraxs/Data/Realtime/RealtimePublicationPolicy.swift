import Foundation

/// Client policy for postgres_changes on tables absent from deployed `supabase_realtime`.
/// Mirrors `lib/realtimePublicationPolicy.ts`.
nonisolated enum RealtimePublicationPolicy {
    static let postgresChangesDisabledTables: Set<String> = [
        "stories",
        "profile_post_likes",
        "achievement_post_likes",
    ]

    static let publicationCandidateTables: Set<String> = [
        "conversation_member_preferences",
        "room_members",
    ]

    static func shouldOpenPostgresChangesWatch(table: String) -> Bool {
        !postgresChangesDisabledTables.contains(table)
    }
}
