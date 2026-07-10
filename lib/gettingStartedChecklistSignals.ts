import type { SupabaseClient } from "@supabase/supabase-js"
import { isDemoUserId } from "@/lib/demo/constants"
import { DEMO_TRADES } from "@/lib/demo/fixtures"
import { getCachedTrades } from "./appDataCache"
import {
  deriveTradeChecklistSignalsFromTrades,
  type TradeChecklistSignals,
} from "./deriveTradeChecklistSignals"

export { deriveTradeChecklistSignalsFromTrades, type TradeChecklistSignals }

export type GettingStartedChecklistSignals = {
  onboardingCompleted: boolean
  hasSeenGettingStartedIntro: boolean
  hasSeenOnboardingCompletePopup: boolean
  accountCount: number
  tradeCount: number
  hasRunAiAnalysis: boolean
  followCount: number
  hasEverJoinedOtherRoom: boolean
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
      accountCount: 2,
      tradeCount: DEMO_TRADES.length,
      hasRunAiAnalysis: true,
      followCount: 8,
      hasEverJoinedOtherRoom: true,
    }
  }

  const cachedTrades = getCachedTrades(userId)
  const cachedTradeSignals = cachedTrades
    ? deriveTradeChecklistSignalsFromTrades(cachedTrades)
    : null

  const [
    profileRes,
    tradesRes,
    accountsRes,
    aiAnalysisRes,
    followRes,
    roomMembersRes,
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
    cachedTradeSignals
      ? Promise.resolve({ count: cachedTradeSignals.tradeCount, error: null })
      : supabase
          .from("trades")
          .select("id", { count: "exact", head: true })
          .eq("user_id", userId),
    supabase
      .from("accounts")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId),
    supabase
      .from("trades")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .not("ai_feedback", "is", null),
    supabase
      .from("followers")
      .select("following_id", { count: "exact", head: true })
      .eq("follower_id", userId),
    supabase
      .from("room_members")
      .select("room_id, rooms(owner_user_id)")
      .eq("user_id", userId),
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
    accountCount: accountsRes.count ?? 0,
    tradeCount: tradesRes.count ?? 0,
    hasRunAiAnalysis: (aiAnalysisRes.count ?? 0) > 0,
    followCount: followRes.count ?? 0,
    hasEverJoinedOtherRoom,
  }
}
