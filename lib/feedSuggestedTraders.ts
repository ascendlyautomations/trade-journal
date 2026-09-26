import type { SupabaseClient } from "@supabase/supabase-js"
import { isDemoModeActive } from "./demo/demoMode"
import { getDemoExploreProfiles } from "./demo/demoExplore"

/** Newest public profiles considered in one request. */
export const SUGGESTED_TRADERS_POOL = 24
/** Rows shown in the desktop rail. */
export const SUGGESTED_TRADERS_LIMIT = 6

const SUGGESTED_TRADER_FIELDS =
  "id, username, name, avatar_url, is_private, trader_type, trading_style" as const

export type SuggestedTrader = {
  id: string
  username: string | null
  name: string | null
  avatar_url: string | null
  is_private?: boolean | null
  trader_type?: string | null
  trading_style?: string | null
}

type BlockRow = {
  blocker_id: string
  blocked_id: string
}

export function blockedPeerIds(
  viewerId: string,
  rows: BlockRow[] | null | undefined
): string[] {
  const ids: string[] = []
  for (const row of rows ?? []) {
    const blocker = String(row.blocker_id ?? "")
    const blocked = String(row.blocked_id ?? "")
    if (blocker === viewerId && blocked) ids.push(blocked)
    else if (blocked === viewerId && blocker) ids.push(blocker)
  }
  return ids
}

/**
 * Public-profile discovery, same visibility as Explore:
 * username present, not private, not the viewer, not already followed, not blocked.
 * Input order is preserved (newest-first from the query).
 */
export function selectSuggestedTraders(
  profiles: SuggestedTrader[],
  options: {
    viewerId: string
    followingIds: Iterable<string>
    blockedIds: Iterable<string>
    limit?: number
  }
): SuggestedTrader[] {
  const following = new Set(options.followingIds)
  const blocked = new Set(options.blockedIds)
  const seen = new Set<string>()
  const limit = options.limit ?? SUGGESTED_TRADERS_LIMIT
  const selected: SuggestedTrader[] = []

  for (const profile of profiles) {
    const id = String(profile?.id ?? "").trim()
    if (!id || seen.has(id)) continue
    if (id === options.viewerId) continue
    if (following.has(id)) continue
    if (blocked.has(id)) continue
    if (profile.is_private === true) continue
    if (!profile.username?.trim()) continue
    seen.add(id)
    selected.push(profile)
    if (selected.length >= limit) break
  }

  return selected
}

export async function fetchSuggestedTraderPool(
  supabase: SupabaseClient,
  viewerId: string
): Promise<{ profiles: SuggestedTrader[]; blockedIds: string[] }> {
  if (isDemoModeActive()) {
    return {
      profiles: getDemoExploreProfiles(),
      blockedIds: [],
    }
  }

  const [profilesRes, blocksRes] = await Promise.all([
    supabase
      .from("profiles")
      .select(SUGGESTED_TRADER_FIELDS)
      .not("username", "is", null)
      .neq("is_private", true)
      .neq("id", viewerId)
      .order("created_at", { ascending: false })
      .limit(SUGGESTED_TRADERS_POOL),
    supabase
      .from("user_blocks")
      .select("blocker_id, blocked_id")
      .or(`blocker_id.eq.${viewerId},blocked_id.eq.${viewerId}`),
  ])

  if (profilesRes.error) {
    console.error("[feed] suggested traders:", profilesRes.error)
    return { profiles: [], blockedIds: [] }
  }

  if (blocksRes.error) {
    console.error("[feed] suggested traders blocks:", blocksRes.error)
    return { profiles: [], blockedIds: [] }
  }

  return {
    profiles: (profilesRes.data ?? []) as SuggestedTrader[],
    blockedIds: blockedPeerIds(
      viewerId,
      (blocksRes.data ?? []) as BlockRow[]
    ),
  }
}
