import type { SupabaseClient } from "@supabase/supabase-js"
import { sumPayoutAchievementTotals } from "./achievementTypes.ts"
import type { ProfileBootstrapSectionCounts } from "./profileDeferredLoads.ts"

/** `section_counts.profile_posts` from `rpc_v1_profile_bootstrap`. */
export function profilePostsCountFromSectionCounts(
  sectionCounts: ProfileBootstrapSectionCounts | null | undefined
): number | null {
  if (!sectionCounts) return null
  const raw = (sectionCounts as { profile_posts?: unknown }).profile_posts
  if (raw === null || raw === undefined) return null
  const n = typeof raw === "number" ? raw : Number(raw)
  return Number.isFinite(n) ? n : null
}

/**
 * Sum payout achievements for a profile (RLS-scoped).
 * Matches iOS `DefaultProfileRepository.fetchPayoutTotal` / bootstrap `payout_total`.
 */
export async function fetchProfilePayoutTotal(
  client: SupabaseClient,
  profileUserId: string
): Promise<number | null> {
  const userId = String(profileUserId ?? "").trim()
  if (!userId) return null

  const { data, error } = await client
    .from("achievements")
    .select("achievement_type, value_numeric")
    .eq("user_id", userId)

  if (error) {
    console.error("[profile] payout total fetch:", error.message)
    return null
  }

  return sumPayoutAchievementTotals(data ?? [])
}

/**
 * Count profile wall posts visible to the current viewer (RLS-scoped head count).
 */
export async function fetchProfilePostsCount(
  client: SupabaseClient,
  profileUserId: string
): Promise<number | null> {
  const userId = String(profileUserId ?? "").trim()
  if (!userId) return null

  const { count, error } = await client
    .from("profile_posts")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)

  if (error) {
    console.error("[profile] posts count fetch:", error.message)
    return null
  }

  return count ?? 0
}
