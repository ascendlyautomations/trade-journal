import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import { isLiveKitConfigured } from "./config.ts"
import { getLiveKitBroadcastRoomPresence } from "./liveKitRoomService.ts"
import { normalizeVisibilityFromRow } from "./tradeRoomBroadcastSession.ts"

export type ExploreLiveTraderNow = {
  broadcastSessionId: string
  roomId: string
  roomSlug: string | null
  roomName: string
  broadcasterUserId: string
  broadcasterDisplayName: string | null
  broadcasterUsername: string | null
  broadcasterAvatarUrl: string | null
  viewerCount: number | null
  startedAt: string
  videoSource: string
}

type BroadcastRow = {
  id: string
  room_id: string
  broadcaster_user_id: string
  started_at: string
  video_source: string
  visibility: string | null
  primary_media_publisher_identity: string | null
  rooms: {
    id: string
    name: string | null
    slug: string | null
    is_private: boolean | null
  } | null
}

/** Active sessions eligible for Explore “Live Traders Now” (public visibility, non-private room). */
export function isExploreDiscoverableLiveBroadcastRow(row: BroadcastRow): boolean {
  const vis = normalizeVisibilityFromRow(row as unknown as Record<string, unknown>)
  if (vis !== "public") return false
  if (row.rooms?.is_private === true) return false
  return true
}

export async function listExploreLiveTradersNow(
  admin: SupabaseClient<Database>,
  options?: { limit?: number; includeViewerCounts?: boolean }
): Promise<ExploreLiveTraderNow[]> {
  const limit = Math.max(1, Math.min(options?.limit ?? 12, 24))

  const { data: rows, error } = await admin
    .from("room_live_broadcasts")
    .select(
      `
      id,
      room_id,
      broadcaster_user_id,
      started_at,
      video_source,
      visibility,
      primary_media_publisher_identity,
      rooms!inner(id, name, slug, is_private)
    `
    )
    .is("ended_at", null)
    .order("started_at", { ascending: false })
    .limit(limit * 2)

  if (error) {
    console.error("[exploreLiveTradersNow] room_live_broadcasts:", error)
    return []
  }
  if (!rows?.length) {
    return []
  }

  const publicRows = (rows as BroadcastRow[]).filter(isExploreDiscoverableLiveBroadcastRow)

  const trimmed = publicRows.slice(0, limit)
  if (trimmed.length === 0) return []

  const broadcasterIds = [...new Set(trimmed.map((r) => r.broadcaster_user_id))]
  const { data: profiles } = await admin
    .from("profiles")
    .select("id, username, name, avatar_url")
    .in("id", broadcasterIds)

  const profileById = new Map(
    (profiles ?? []).map((p) => [String(p.id), p])
  )

  const withCounts = options?.includeViewerCounts !== false && isLiveKitConfigured()

  const items: ExploreLiveTraderNow[] = []
  for (const row of trimmed) {
    const room = row.rooms
    const profile = profileById.get(row.broadcaster_user_id)
    let viewerCount: number | null = null
    if (withCounts) {
      try {
        const presence = await getLiveKitBroadcastRoomPresence(
          row.room_id,
          row.broadcaster_user_id,
          {
            primaryMediaPublisherIdentity:
              row.primary_media_publisher_identity?.trim() || null,
          }
        )
        viewerCount = presence?.viewerCount ?? null
      } catch {
        viewerCount = null
      }
    }

    items.push({
      broadcastSessionId: row.id,
      roomId: row.room_id,
      roomSlug: room?.slug?.trim() || null,
      roomName: room?.name?.trim() || "Trade Room",
      broadcasterUserId: row.broadcaster_user_id,
      broadcasterDisplayName: profile?.name?.trim() || null,
      broadcasterUsername: profile?.username?.trim() || null,
      broadcasterAvatarUrl: profile?.avatar_url?.trim() || null,
      viewerCount,
      startedAt: row.started_at,
      videoSource: row.video_source?.trim() || "camera",
    })
  }

  return items
}
