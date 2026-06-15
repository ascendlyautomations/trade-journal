import type { SupabaseClient } from "@supabase/supabase-js"
import {
  isExcludedDiscoveryRoomSlug,
  isPublicDiscoveryRoom,
} from "@/lib/betaHub"

export type PopularTradeRoom = {
  id: string
  name: string
  description: string | null
  slug: string | null
  memberCount: number
}

const DEFAULT_LIMIT = 12

function normalizePopularRoomRow(row: {
  id: string
  name: string
  description?: string | null
  slug?: string | null
  member_count?: number | null
}): PopularTradeRoom | null {
  if (isExcludedDiscoveryRoomSlug(row.slug)) return null
  return {
    id: row.id,
    name: row.name,
    description: row.description ?? null,
    slug: row.slug ?? null,
    memberCount: Number(row.member_count) || 0,
  }
}

/** Prefer RPC with member counts; fall back to profile-public rooms without counts. */
export async function fetchPopularTradeRooms(
  supabase: SupabaseClient,
  limit = DEFAULT_LIMIT
): Promise<PopularTradeRoom[]> {
  const capped = Math.max(1, Math.min(limit, 50))

  const { data: rpcRows, error: rpcError } = await supabase.rpc(
    "popular_trade_rooms",
    { p_limit: capped }
  )

  if (!rpcError && Array.isArray(rpcRows)) {
    return rpcRows
      .map((row) =>
        normalizePopularRoomRow(
          row as {
            id: string
            name: string
            description?: string | null
            slug?: string | null
            member_count?: number | null
          }
        )
      )
      .filter((row): row is PopularTradeRoom => row != null)
  }

  if (rpcError) {
    console.warn("[popularTradeRooms] rpc fallback:", rpcError.message)
  }

  const { data: rooms, error } = await supabase
    .from("rooms")
    .select("id, name, description, slug, show_on_profile")
    .not("owner_user_id", "is", null)
    .limit(capped * 3)

  if (error) {
    console.error("[popularTradeRooms] rooms fetch:", error)
    return []
  }

  return (rooms ?? [])
    .filter((room) => isPublicDiscoveryRoom(room))
    .slice(0, capped)
    .map((room) => ({
      id: room.id,
      name: room.name,
      description: room.description ?? null,
      slug: room.slug ?? null,
      memberCount: 0,
    }))
}
