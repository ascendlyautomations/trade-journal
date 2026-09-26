/**
 * Phase 3 — client policy for postgres_changes on tables absent from deployed
 * `supabase_realtime`. Publication changes are a separate decision.
 *
 * Disabled tables: the watch is omitted. Another path already keeps state correct.
 * Candidates: the watch stays, because live cross-client updates are the intended behavior.
 */

export const REALTIME_POSTGRES_CHANGES_DISABLED_TABLES = new Set<string>([
  "stories",
  "profile_post_likes",
  "achievement_post_likes",
])

export const REALTIME_PUBLICATION_CANDIDATE_TABLES = [
  "conversation_member_preferences",
  "room_members",
] as const

export function isPostgresChangesWatchEnabled(table: string): boolean {
  return !REALTIME_POSTGRES_CHANGES_DISABLED_TABLES.has(table)
}
