import { RoomServiceClient, TrackSource } from "livekit-server-sdk"
import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import { readLiveKitServerConfig } from "./config.ts"
import {
  legacySectionLiveKitRoomName,
  liveKitBroadcastRoomName,
  liveKitRoomName,
} from "./liveKitRoomName.ts"

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

async function listLegacyVoiceSectionIdsForRoom(
  admin: SupabaseClient<Database>,
  roomId: string
): Promise<string[]> {
  const { data, error } = await admin
    .from("room_sections")
    .select("id, live_kind")
    .eq("room_id", roomId)

  if (error) {
    console.error("[livekit] list legacy voice sections failed", error.message)
    return []
  }

  return (data ?? [])
    .filter((row) => {
      const kind = (row.live_kind ?? "text").toLowerCase()
      return kind === "voice_open" || kind === "voice_stage"
    })
    .map((row) => row.id)
}

/** Removes a user from the Trade Room shared LiveKit voice room (+ legacy section rooms). */
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

  const lkRoomNames = new Set<string>([
    liveKitRoomName(roomId),
    liveKitBroadcastRoomName(roomId),
  ])
  for (const sectionId of await listLegacyVoiceSectionIdsForRoom(admin, roomId)) {
    lkRoomNames.add(legacySectionLiveKitRoomName(roomId, sectionId))
  }

  const errors: string[] = []
  let removed = 0

  for (const lkRoom of lkRoomNames) {
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

  return { attempted: lkRoomNames.size, removed, errors }
}

export async function setLiveKitStagePublish(
  roomId: string,
  targetUserId: string,
  canPublish: boolean
): Promise<void> {
  const client = getLiveKitRoomServiceClient()
  if (!client) {
    throw new Error("LiveKit is not configured on the server.")
  }

  const lkRoom = liveKitRoomName(roomId)
  await client.updateParticipant(lkRoom, targetUserId, {
    permission: {
      canPublish,
      canSubscribe: true,
      canPublishData: true,
      canPublishSources: canPublish ? [TrackSource.MICROPHONE] : [],
    },
  })
}

export async function setLiveKitBroadcastParticipantMic(
  roomId: string,
  targetUserId: string,
  canPublishMic: boolean
): Promise<void> {
  const client = getLiveKitRoomServiceClient()
  if (!client) {
    throw new Error("LiveKit is not configured on the server.")
  }

  await client.updateParticipant(liveKitBroadcastRoomName(roomId), targetUserId, {
    permission: {
      canPublish: canPublishMic,
      canSubscribe: true,
      canPublishData: true,
      canPublishSources: canPublishMic ? [TrackSource.MICROPHONE] : [],
    },
  })
}

export async function removeLiveKitBroadcastParticipant(
  roomId: string,
  targetUserId: string
): Promise<void> {
  const client = getLiveKitRoomServiceClient()
  if (!client) {
    throw new Error("LiveKit is not configured on the server.")
  }
  await client.removeParticipant(liveKitBroadcastRoomName(roomId), targetUserId)
}

export async function muteLiveKitBroadcastParticipantMicrophone(
  roomId: string,
  targetUserId: string,
  muted: boolean
): Promise<void> {
  const client = getLiveKitRoomServiceClient()
  if (!client) {
    throw new Error("LiveKit is not configured on the server.")
  }
  const lkRoom = liveKitBroadcastRoomName(roomId)
  if (muted) {
    await client.updateParticipant(lkRoom, targetUserId, {
      permission: {
        canPublish: false,
        canSubscribe: true,
        canPublishData: true,
        canPublishSources: [],
      },
    })
    const participants = await client.listParticipants(lkRoom)
    const target = participants.find((p) => p.identity === targetUserId)
    for (const track of target?.tracks ?? []) {
      if (track.sid && track.source === TrackSource.MICROPHONE) {
        try {
          await client.mutePublishedTrack(lkRoom, targetUserId, track.sid, true)
        } catch {
          // Participant may have already disconnected.
        }
      }
    }
  } else {
    await setLiveKitBroadcastParticipantMic(roomId, targetUserId, true)
  }
}

export async function countLiveKitBroadcastViewers(
  roomId: string,
  broadcasterUserId: string
): Promise<number | null> {
  const client = getLiveKitRoomServiceClient()
  if (!client) return null

  try {
    const participants = await client.listParticipants(
      liveKitBroadcastRoomName(roomId)
    )
    return participants.filter((p) => p.identity !== broadcasterUserId).length
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    if (/not found|does not exist|404/i.test(message)) {
      return 0
    }
    console.warn("[livekit/broadcast] list participants failed", message)
    return null
  }
}
