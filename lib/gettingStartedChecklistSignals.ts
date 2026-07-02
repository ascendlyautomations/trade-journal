import type { SupabaseClient } from "@supabase/supabase-js"
import { isDemoUserId } from "@/lib/demo/constants"
import { DEMO_TRADES } from "@/lib/demo/fixtures"

export type GettingStartedChecklistSignals = {
  onboardingCompleted: boolean
  hasSeenGettingStartedIntro: boolean
  hasSeenOnboardingCompletePopup: boolean
  tradeCount: number
  profilePostCount: number
  followCount: number
  hasEverJoinedOtherRoom: boolean
  hasPublicTrade: boolean
  /** Most recent private trade — used to deep-link into trade edit. */
  firstPrivateTradeId: string | null
}

/** Profile onboarding flags from UserProfileProvider — skips duplicate profiles query. */
export type GettingStartedPreloadedProfileSignals = {
  onboardingCompleted: boolean
  hasSeenGettingStartedIntro: boolean
  hasSeenOnboardingCompletePopup: boolean
}

export async function fetchGettingStartedChecklistSignals(
  supabase: SupabaseClient,
  userId: string,
  preloadedProfileSignals?: GettingStartedPreloadedProfileSignals
): Promise<GettingStartedChecklistSignals> {
  if (isDemoUserId(userId)) {
    return {
      onboardingCompleted: true,
      hasSeenGettingStartedIntro: true,
      hasSeenOnboardingCompletePopup: true,
      tradeCount: DEMO_TRADES.length,
      profilePostCount: 3,
      followCount: 8,
      hasEverJoinedOtherRoom: true,
      hasPublicTrade: true,
      firstPrivateTradeId: DEMO_TRADES[0]?.id ?? null,
    }
  }

  const [
    profileRes,
    tradesRes,
    profilePostsRes,
    followRes,
    roomMembersRes,
    publicTradesRes,
    privateTradeRes,
  ] = await Promise.all([
    preloadedProfileSignals
      ? Promise.resolve({
          data: {
            onboarding_completed: preloadedProfileSignals.onboardingCompleted,
            has_seen_getting_started_intro:
              preloadedProfileSignals.hasSeenGettingStartedIntro,
            has_seen_onboarding_complete_popup:
              preloadedProfileSignals.hasSeenOnboardingCompletePopup,
          },
          error: null,
        })
      : supabase
          .from("profiles")
          .select(
            "onboarding_completed, has_seen_getting_started_intro, has_seen_onboarding_complete_popup"
          )
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

  if (profileRes.error) {
    console.error(
      "fetchGettingStartedChecklistSignals profile:",
      profileRes.error.message,
      profileRes.error.code
    )
  }

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
    hasSeenGettingStartedIntro:
      profileRes.data?.has_seen_getting_started_intro === true,
    hasSeenOnboardingCompletePopup:
      profileRes.data?.has_seen_onboarding_complete_popup === true,
    tradeCount: tradesRes.count ?? 0,
    profilePostCount: profilePostsRes.count ?? 0,
    followCount: followRes.count ?? 0,
    hasEverJoinedOtherRoom,
    hasPublicTrade: (publicTradesRes.count ?? 0) > 0,
    firstPrivateTradeId:
      privateTradeRes.data?.id != null
        ? String(privateTradeRes.data.id)
        : null,
  }
}
