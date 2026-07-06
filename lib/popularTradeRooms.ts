import type { SupabaseClient } from "@supabase/supabase-js"
import { isPublicDiscoveryRoom } from "@/lib/betaHub"
import { filterRoomsWithPublicOwners } from "@/lib/publicProfileDiscovery"
import { isDemoSupabaseBlocked } from "@/lib/demo/demoSupabaseGuard"
import {
  getDemoPopularTradeRooms,
  searchDemoPopularTradeRooms,
} from "@/lib/demo/demoRooms"

export type PopularTradeRoom = {
  id: string
  name: string
  description: string | null
  slug: string | null
  memberCount: number
  imageUrl: string | null
  avatarUrl: string | null
}

const DEFAULT_LIMIT = 12

/** Matches community sidebar: image_url first, then avatar_url. */
export function resolveRoomAvatarUrl(room: {
  imageUrl?: string | null
  avatarUrl?: string | null
}): string | null {
  for (const value of [room.imageUrl, room.avatarUrl]) {
    if (value != null && String(value).trim() !== "") {
      return String(value).trim()
    }
  }
  return null
}

export function roomDisplayInitials(name: string): string {
  const trimmed = name.trim()
  if (!trimmed) return "?"
  const parts = trimmed.split(/\s+/).filter(Boolean)
  if (parts.length >= 2) {
    return (parts[0].charAt(0) + parts[1].charAt(0)).toUpperCase()
  }
  return trimmed.slice(0, 2).toUpperCase()
}

function sanitizeRoomSearchQuery(value: string): string {
  return value.replace(/[%_]/g, "").trim()
}

function mapRoomRow(
  row: {
    id: string
    name: string
    description?: string | null
    slug?: string | null
    member_count?: number | null
    image_url?: string | null
    avatar_url?: string | null
    show_on_profile?: boolean | null
    is_private?: boolean | null
  },
  memberCount?: number
): PopularTradeRoom | null {
  if (!isPublicDiscoveryRoom(row)) return null
  return {
    id: row.id,
    name: row.name,
    description: row.description ?? null,
    slug: row.slug ?? null,
    memberCount:
      memberCount ?? (Number(row.member_count) || 0),
    imageUrl: row.image_url ?? null,
    avatarUrl: row.avatar_url ?? null,
  }
}

async function attachRoomImages(
  supabase: SupabaseClient,
  rooms: PopularTradeRoom[]
): Promise<PopularTradeRoom[]> {
  if (rooms.length === 0) return rooms

  const ids = rooms.map((room) => room.id)
  const { data, error } = await supabase
    .from("rooms")
    .select("id, image_url")
    .in("id", ids)

  if (error) {
    console.warn("[popularTradeRooms] room images:", error.message)
    return rooms
  }

  const byId = new Map(
    (data ?? []).map((row) => [String(row.id), row.image_url ?? null])
  )

  return rooms.map((room) => ({
    ...room,
    imageUrl: byId.get(room.id) ?? room.imageUrl,
  }))
}

/** Prefer RPC with member counts; fall back to profile-public rooms without counts. */
export async function fetchPopularTradeRooms(
  supabase: SupabaseClient,
  limit = DEFAULT_LIMIT
): Promise<PopularTradeRoom[]> {
  if (isDemoSupabaseBlocked()) {
    return getDemoPopularTradeRooms().slice(0, limit)
  }

  const capped = Math.max(1, Math.min(limit, 50))

  const { data: rpcRows, error: rpcError } = await supabase.rpc(
    "popular_trade_rooms",
    { p_limit: capped }
  )

  if (!rpcError && Array.isArray(rpcRows)) {
    const popular = rpcRows
      .map((row) =>
        mapRoomRow(
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
    return attachRoomImages(supabase, popular)
  }

  if (rpcError) {
    console.warn("[popularTradeRooms] rpc fallback:", rpcError.message)
  }

  const { data: rooms, error } = await supabase
    .from("rooms")
    .select(
      "id, name, description, slug, show_on_profile, is_private, image_url, owner_user_id"
    )
    .not("owner_user_id", "is", null)
    .limit(capped * 3)

  if (error) {
    console.error("[popularTradeRooms] rooms fetch:", error)
    return []
  }

  const publicOwnerRooms = await filterRoomsWithPublicOwners(supabase, rooms ?? [])

  return publicOwnerRooms
    .filter((room) => isPublicDiscoveryRoom(room))
    .slice(0, capped)
    .map((room) =>
      mapRoomRow(room as Parameters<typeof mapRoomRow>[0], 0)
    )
    .filter((row): row is PopularTradeRoom => row != null)
}

/** Public discovery search by room name or slug (debounce in UI). */
export async function searchPublicTradeRooms(
  supabase: SupabaseClient,
  query: string,
  limit = 20
): Promise<PopularTradeRoom[]> {
  if (isDemoSupabaseBlocked()) {
    return searchDemoPopularTradeRooms(query).slice(0, limit)
  }

  const trimmed = sanitizeRoomSearchQuery(query)
  if (!trimmed) return []

  const capped = Math.max(1, Math.min(limit, 50))

  const { data: rpcRows, error: rpcError } = await supabase.rpc(
    "search_public_trade_rooms",
    { p_query: trimmed, p_limit: capped }
  )

  if (!rpcError && Array.isArray(rpcRows)) {
    return rpcRows
      .map((row) =>
        mapRoomRow(
          row as {
            id: string
            name: string
            description?: string | null
            slug?: string | null
            member_count?: number | null
            image_url?: string | null
          }
        )
      )
      .filter((row): row is PopularTradeRoom => row != null)
  }

  if (rpcError) {
    console.warn("[popularTradeRooms] search rpc fallback:", rpcError.message)
  }

  const pattern = `%${trimmed}%`

  const { data: rooms, error } = await supabase
    .from("rooms")
    .select(
      "id, name, description, slug, image_url, show_on_profile, is_private, owner_user_id"
    )
    .not("owner_user_id", "is", null)
    .or(`name.ilike.${pattern},slug.ilike.${pattern}`)
    .order("name", { ascending: true })
    .limit(capped * 3)

  if (error) {
    console.error("[popularTradeRooms] search:", error)
    return []
  }

  const publicOwnerRooms = await filterRoomsWithPublicOwners(supabase, rooms ?? [])

  return publicOwnerRooms
    .filter((room) => isPublicDiscoveryRoom(room))
    .slice(0, capped)
    .map((room) => mapRoomRow(room as Parameters<typeof mapRoomRow>[0], 0))
    .filter((row): row is PopularTradeRoom => row != null)
}
