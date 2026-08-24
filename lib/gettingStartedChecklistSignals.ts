import type { SupabaseClient } from "@supabase/supabase-js"
import { isDemoUserId } from "@/lib/demo/constants"
import { DEMO_TRADES } from "@/lib/demo/fixtures"
import { getCachedTrades } from "./appDataCache"
import { deriveTradeChecklistSignalsFromTrades } from "./deriveTradeChecklistSignals"
import { getSessionFollowingIds } from "./backendV2/sessionBootstrapCache.ts"
import { readDashboardBootstrapCache } from "./backendV2/dashboardBootstrapCache.ts"
import { BackendV2RpcError } from "./backendV2/rpcClient.ts"
import { BackendV2RpcNames } from "./backendV2/versioning.ts"
import {
  clearGettingStartedRpcUnavailableCache,
  isGettingStartedRpcCachedUnavailable,
  isGettingStartedRpcUnavailable,
  markGettingStartedRpcUnavailable,
} from "./gettingStartedRpcAvailability.ts"
import { decodeGettingStartedSignalsRpc } from "./gettingStartedSignalsRpc.ts"
import { mergeGettingStartedSignals } from "./gettingStartedSignalsMerge.ts"

export type {
  GettingStartedChecklistSignals,
  GettingStartedLocalOverrides,
  GettingStartedPreloadedProfileSignals,
} from "./gettingStartedChecklistSignals.types.ts"

export {
  deriveTradeChecklistSignalsFromTrades,
  type TradeChecklistSignals,
} from "./deriveTradeChecklistSignals"

export { mergeGettingStartedSignals } from "./gettingStartedSignalsMerge.ts"
export { isGettingStartedRpcUnavailable } from "./gettingStartedRpcAvailability.ts"

import type {
  GettingStartedChecklistSignals,
  GettingStartedLocalOverrides,
  GettingStartedPreloadedProfileSignals,
} from "./gettingStartedChecklistSignals.types.ts"

const checklistSignalsInFlight = new Map<
  string,
  Promise<GettingStartedChecklistSignals>
>()

/** @internal */
export function resetGettingStartedChecklistSignalsInFlightForTests(): void {
  checklistSignalsInFlight.clear()
}

export function resolveGettingStartedLocalOverrides(
  userId: string,
  preloadedProfileSignals?: GettingStartedPreloadedProfileSignals
): GettingStartedLocalOverrides {
  const cachedTrades = getCachedTrades(userId)
  const trade = cachedTrades
    ? deriveTradeChecklistSignalsFromTrades(cachedTrades)
    : null
  const sessionFollowing = getSessionFollowingIds(userId)
  const dashboard = readDashboardBootstrapCache(userId)
  const dashboardTradeCount =
    trade == null
      ? (dashboard?.data.trade_window_meta.total_trade_count ?? null)
      : null

  return {
    profile: preloadedProfileSignals,
    trade,
    dashboardTradeCount,
    followCount: sessionFollowing ? sessionFollowing.length : null,
  }
}

async function fetchGettingStartedSignalsRpc(
  supabase: SupabaseClient
): Promise<GettingStartedChecklistSignals> {
  const { data, error } = await supabase.rpc(
    BackendV2RpcNames.gettingStarted,
    {}
  )
  if (error) {
    throw new BackendV2RpcError(
      error.code ?? "rpc_error",
      error.message ?? "Getting Started RPC failed",
      BackendV2RpcNames.gettingStarted,
      error
    )
  }
  clearGettingStartedRpcUnavailableCache()
  return decodeGettingStartedSignalsRpc(data)
}

/** Legacy seven-request fan-out — used when RPC is not deployed. */
export async function fetchGettingStartedChecklistSignalsLegacy(
  supabase: SupabaseClient,
  userId: string,
  preloadedProfileSignals?: GettingStartedPreloadedProfileSignals
): Promise<GettingStartedChecklistSignals> {
  const overrides = resolveGettingStartedLocalOverrides(
    userId,
    preloadedProfileSignals
  )

  const [
    profileRes,
    tradesRes,
    profilePostsRes,
    followRes,
    roomMembersRes,
    publicTradesRes,
    privateTradeRes,
  ] = await Promise.all([
    overrides.profile
      ? Promise.resolve({
          data: {
            onboarding_completed: overrides.profile.onboardingCompleted,
            has_seen_getting_started_intro:
              overrides.profile.hasSeenGettingStartedIntro,
            has_seen_onboarding_complete_popup:
              overrides.profile.hasSeenOnboardingCompletePopup,
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
    overrides.trade
      ? Promise.resolve({ count: overrides.trade.tradeCount, error: null })
      : overrides.dashboardTradeCount != null
        ? Promise.resolve({
            count: overrides.dashboardTradeCount,
            error: null,
          })
        : supabase
            .from("trades")
            .select("id", { count: "exact", head: true })
            .eq("user_id", userId),
    supabase
      .from("profile_posts")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId),
    overrides.followCount != null
      ? Promise.resolve({ count: overrides.followCount, error: null })
      : supabase
          .from("followers")
          .select("following_id", { count: "exact", head: true })
          .eq("follower_id", userId),
    supabase
      .from("room_members")
      .select("room_id, rooms(owner_user_id)")
      .eq("user_id", userId),
    overrides.trade
      ? Promise.resolve({
          count: overrides.trade.hasPublicTrade ? 1 : 0,
          error: null,
        })
      : supabase
          .from("trades")
          .select("id", { count: "exact", head: true })
          .eq("user_id", userId)
          .eq("is_public", true),
    overrides.trade
      ? Promise.resolve({
          data: overrides.trade.firstPrivateTradeId
            ? { id: overrides.trade.firstPrivateTradeId }
            : null,
          error: null,
        })
      : supabase
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

export async function fetchGettingStartedChecklistSignals(
  supabase: SupabaseClient,
  userId: string,
  preloadedProfileSignals?: GettingStartedPreloadedProfileSignals
): Promise<GettingStartedChecklistSignals> {
  const existing = checklistSignalsInFlight.get(userId)
  if (existing) return existing

  const run = (async (): Promise<GettingStartedChecklistSignals> => {
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

    const overrides = resolveGettingStartedLocalOverrides(
      userId,
      preloadedProfileSignals
    )

    if (!isGettingStartedRpcCachedUnavailable()) {
      try {
        const rpc = await fetchGettingStartedSignalsRpc(supabase)
        return mergeGettingStartedSignals(rpc, overrides)
      } catch (err) {
        if (!isGettingStartedRpcUnavailable(err)) throw err
        markGettingStartedRpcUnavailable()
      }
    }

    const legacy = await fetchGettingStartedChecklistSignalsLegacy(
      supabase,
      userId,
      preloadedProfileSignals
    )
    return mergeGettingStartedSignals(legacy, overrides)
  })()

  checklistSignalsInFlight.set(userId, run)
  try {
    return await run
  } finally {
    if (checklistSignalsInFlight.get(userId) === run) {
      checklistSignalsInFlight.delete(userId)
    }
  }
}
