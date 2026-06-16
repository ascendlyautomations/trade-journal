import type { SupabaseClient } from "@supabase/supabase-js"

export type GettingStartedChecklistSignals = {
  onboardingCompleted: boolean
  tradeCount: number
  profilePostCount: number
  feedPostCount: number
  followCount: number
  hasEverJoinedOtherRoom: boolean
  hasPublicTrade: boolean
  /** Most recent private trade — used to deep-link into trade edit. */
  firstPrivateTradeId: string | null
}

export async function fetchGettingStartedChecklistSignals(
  supabase: SupabaseClient,
  userId: string
): Promise<GettingStartedChecklistSignals> {
  const [
    profileRes,
    tradesRes,
    profilePostsRes,
    feedPostsRes,
    followRes,
    roomMembersRes,
    publicTradesRes,
    privateTradeRes,
  ] = await Promise.all([
    supabase
      .from("profiles")
      .select("onboarding_completed")
      .eq("id", userId)
      .maybeSingle(),
    supabase
      .from("trades")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId),
    supabase
      .from("profile_posts")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId),
    supabase
      .from("posts")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId),
    supabase
      .from("followers")
      .select("following_id", { count: "exact", head: true })
      .eq("follower_id", userId),
    supabase
      .from("room_members")
      .select("room_id, rooms(owner_user_id)")
      .eq("user_id", userId),
    supabase
      .from("trades")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .eq("is_public", true),
    supabase
      .from("trades")
      .select("id")
      .eq("user_id", userId)
      .eq("is_public", false)
      .neq("mode", "backtest")
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle(),
  ])

  const hasEverJoinedOtherRoom = (roomMembersRes.data ?? []).some(
    (row: {
      rooms?:
        | { owner_user_id?: string }
        | { owner_user_id?: string }[]
        | null
    }) => {
      const rooms = row.rooms
      const ownerId = Array.isArray(rooms)
        ? rooms[0]?.owner_user_id
        : rooms?.owner_user_id
      return ownerId != null && ownerId !== userId
    }
  )

  return {
    onboardingCompleted: profileRes.data?.onboarding_completed === true,
    tradeCount: tradesRes.count ?? 0,
    profilePostCount: profilePostsRes.count ?? 0,
    feedPostCount: feedPostsRes.count ?? 0,
    followCount: followRes.count ?? 0,
    hasEverJoinedOtherRoom,
    hasPublicTrade: (publicTradesRes.count ?? 0) > 0,
    firstPrivateTradeId:
      privateTradeRes.data?.id != null
        ? String(privateTradeRes.data.id)
        : null,
  }
}
