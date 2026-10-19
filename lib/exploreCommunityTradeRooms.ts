import type { SupabaseClient } from "@supabase/supabase-js"
import { isDemoSupabaseBlocked } from "./demo/demoSupabaseGuard.ts"
import { getDemoPopularTradeRooms } from "./demo/demoRooms.ts"
import type { PopularTradeRoom } from "./popularTradeRooms.ts"
import { parseExploreSuggestedDiscoveryRoomsForViewer } from "./exploreCommunityTradeRoomsSelection.ts"

/** Initial grid: 3 × 2 on desktop. */
export const EXPLORE_COMMUNITY_ROOMS_PAGE_SIZE = 6

/** Native Explore `loadSuggestedTradeRooms` discovery fetch cap. */
export const EXPLORE_SUGGESTED_ROOMS_DISCOVERY_LIMIT = 12

export type ExploreSuggestedRoomsFetchStatus = "ok" | "rpc_error"

export type ExploreSuggestedTradeRoomsResult = {
  status: ExploreSuggestedRoomsFetchStatus
  rooms: PopularTradeRoom[]
  errorMessage?: string
  /** Which RPC mode populated `rooms` (suggested first, then popular). */
  discoveryMode?: "suggested" | "popular"
}

export {
  isOfficialDiscoveryTradeRoom,
  isUserCommunityTradeRoom,
  mapExploreSuggestedDiscoveryRoom,
  mapExploreCommunityDiscoveryRoom,
  mergeExploreCommunityRooms,
} from "./exploreCommunityTradeRoomsSelection.ts"

type DiscoveryPayload = {
  data?: {
    rooms?: unknown
  }
}

/**
 * Mirrors native `ExploreViewModel.loadSuggestedTradeRooms`:
 * `rpc_v1_trade_room_discovery` suggested → popular, scope `all`, limit 12.
 */
async function fetchDiscoveryMode(
  supabase: SupabaseClient,
  mode: "suggested" | "popular",
  limit: number
): Promise<ExploreSuggestedTradeRoomsResult> {
  const { data, error } = await supabase.rpc("rpc_v1_trade_room_discovery", {
    p_mode: mode,
    p_scope: "all",
    p_limit: Math.min(Math.max(limit, 1), 50),
  })

  if (error) {
    console.error(`[explore] trade room discovery (${mode}):`, error)
    return {
      status: "rpc_error",
      rooms: [],
      errorMessage: error.message,
    }
  }

  const payload = data as DiscoveryPayload
  const rooms = parseExploreSuggestedDiscoveryRoomsForViewer(
    payload.data?.rooms
  )

  return {
    status: "ok",
    rooms,
    discoveryMode: mode,
  }
}

export async function fetchExploreSuggestedTradeRooms(
  supabase: SupabaseClient,
  options: { limit?: number } = {}
): Promise<ExploreSuggestedTradeRoomsResult> {
  const limit = Math.max(
    1,
    Math.min(
      options.limit ?? EXPLORE_SUGGESTED_ROOMS_DISCOVERY_LIMIT,
      50
    )
  )

  if (isDemoSupabaseBlocked()) {
    return {
      status: "ok",
      rooms: getDemoPopularTradeRooms().slice(0, limit),
      discoveryMode: "popular",
    }
  }

  const suggested = await fetchDiscoveryMode(supabase, "suggested", limit)
  if (suggested.status === "rpc_error") {
    return suggested
  }
  if (suggested.rooms.length > 0) {
    return suggested
  }

  const popular = await fetchDiscoveryMode(supabase, "popular", limit)
  if (popular.status === "rpc_error") {
    return popular
  }
  return popular
}

/** @deprecated Use fetchExploreSuggestedTradeRooms — bootstrap/cursor path removed. */
export async function fetchExploreCommunityTradeRoomsPage(
  supabase: SupabaseClient,
  _options: { limit?: number; popularCursor?: string | null } = {}
): Promise<{
  status: ExploreSuggestedRoomsFetchStatus
  rooms: PopularTradeRoom[]
  nextCursor: string | null
  errorMessage?: string
}> {
  const result = await fetchExploreSuggestedTradeRooms(supabase)
  return {
    status: result.status,
    rooms: result.rooms,
    nextCursor: null,
    errorMessage: result.errorMessage,
  }
}
