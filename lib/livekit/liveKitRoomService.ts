import { RoomServiceClient, TrackSource } from "livekit-server-sdk"
import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import { readLiveKitServerConfig } from "./config.ts"
import { liveKitRoomName } from "./liveKitRoomName.ts"

let cachedClient: RoomServiceClient | null = null

export function getLiveKitRoomServiceClient(): RoomServiceClient | null {
  const config = readLiveKitServerConfig()
  if (!config) return null
  if (!cachedClient) {
    cachedClient = new RoomServiceClient(
      config.livekitUrl,
      config.apiKey,
      config.apiSecret
    )
  }
  return cachedClient
}

export async function listVoiceSectionIdsForRoom(
  admin: SupabaseClient<Database>,
  roomId: string
): Promise<string[]> {
  const { data, error } = await admin
    .from("room_sections")
    .select("id, live_kind")
    .eq("room_id", roomId)

  if (error) {
    console.error("[livekit] list voice sections failed", error.message)
    return []
  }

  return (data ?? [])
    .filter((row) => {
      const kind = (row.live_kind ?? "text").toLowerCase()
      return kind === "voice_open" || kind === "voice_stage"
    })
    .map((row) => row.id)
}

/** Removes a user from every LiveKit voice room tied to a Trade Room. */
export async function disconnectUserFromTradeRoomLiveKit(
  admin: SupabaseClient<Database>,
  roomId: string,
  userId: string
): Promise<{ attempted: number; removed: number; errors: string[] }> {
  const client = getLiveKitRoomServiceClient()
  if (!client) {
    return {
      attempted: 0,
      removed: 0,
      errors: ["LiveKit is not configured on the server."],
    }
  }

  const sectionIds = await listVoiceSectionIdsForRoom(admin, roomId)
  const errors: string[] = []
  let removed = 0

  for (const sectionId of sectionIds) {
    const lkRoom = liveKitRoomName(roomId, sectionId)
    try {
      await client.removeParticipant(lkRoom, userId)
      removed += 1
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err)
      if (/not found|does not exist|404/i.test(message)) {
        continue
      }
      errors.push(`${lkRoom}: ${message}`)
    }
  }

  return { attempted: sectionIds.length, removed, errors }
}

export async function setLiveKitStagePublish(
  roomId: string,
  sectionId: string,
  targetUserId: string,
  canPublish: boolean
): Promise<void> {
  const client = getLiveKitRoomServiceClient()
  if (!client) {
    throw new Error("LiveKit is not configured on the server.")
  }

  const lkRoom = liveKitRoomName(roomId, sectionId)
  await client.updateParticipant(lkRoom, targetUserId, {
    permission: {
      canPublish,
      canSubscribe: true,
      canPublishData: true,
      canPublishSources: canPublish ? [TrackSource.MICROPHONE] : [],
    },
  })
}
