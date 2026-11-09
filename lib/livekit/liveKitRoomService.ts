import { RoomServiceClient, TrackSource } from "livekit-server-sdk"
import { primaryPublisherHasPublishableVideo } from "./obsPrimaryMediaReadiness.ts"
import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import { readLiveKitServerConfig } from "./config.ts"
import {
  legacySectionLiveKitRoomName,
  liveKitBroadcastRoomName,
  liveKitRoomName,
} from "./liveKitRoomName.ts"
import { summarizeGeneralVoicePresence } from "./tradeRoomGeneralVoicePresence.ts"

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

/** Removes a user from General Voice (+ legacy section voice rooms), not broadcast. */
export async function disconnectUserFromTradeRoomGeneralVoice(
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

  const lkRoomNames = new Set<string>([liveKitRoomName(roomId)])
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

export async function muteLiveKitGeneralVoiceParticipantMicrophone(
  roomId: string,
  targetUserId: string,
  muted: boolean
): Promise<void> {
  const client = getLiveKitRoomServiceClient()
  if (!client) {
    throw new Error("LiveKit is not configured on the server.")
  }
  const lkRoom = liveKitRoomName(roomId)
  if (muted) {
    const participants = await client.listParticipants(lkRoom)
    const target = participants.find((p) => p.identity === targetUserId)
    for (const track of target?.tracks ?? []) {
      if (track.sid && track.source === TrackSource.MICROPHONE) {
        try {
          await client.mutePublishedTrack(lkRoom, targetUserId, track.sid, true)
        } catch {
          // Participant may have disconnected.
        }
      }
    }
  }
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

export function isLiveKitParticipantAbsentError(message: string): boolean {
  return /not found|does not exist|404|participant/i.test(message)
}

/** Updates mic publish permission only when the identity is already in the broadcast room. */
export async function setLiveKitBroadcastParticipantMicWhenConnected(
  roomId: string,
  targetUserId: string,
  canPublishMic: boolean
): Promise<{ attempted: boolean; skippedAbsent: boolean; livekitRoom: string }> {
  const livekitRoom = liveKitBroadcastRoomName(roomId)
  const identities = await listLiveKitBroadcastParticipantIdentities(roomId)
  if (!identities.includes(targetUserId)) {
    return { attempted: false, skippedAbsent: true, livekitRoom }
  }
  await setLiveKitBroadcastParticipantMic(roomId, targetUserId, canPublishMic)
  return { attempted: true, skippedAbsent: false, livekitRoom }
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

export async function listLiveKitBroadcastParticipantIdentities(
  roomId: string
): Promise<string[]> {
  const client = getLiveKitRoomServiceClient()
  if (!client) return []
  try {
    const participants = await client.listParticipants(
      liveKitBroadcastRoomName(roomId)
    )
    return participants
      .map((p) => p.identity?.trim())
      .filter((id): id is string => Boolean(id))
  } catch {
    return []
  }
}

export type LiveKitBroadcastPresence = {
  /** Host browser/SDK participant (broadcaster_user_id). */
  hostConnected: boolean
  /** OBS / Ingress primary publisher when configured (distinct identity). */
  primaryMediaPublisherConnected: boolean
  /** True if either host or primary program publisher is in the room. */
  broadcasterConnected: boolean
  viewerCount: number
}

/** Single LiveKit listParticipants call for broadcast room (avoids duplicate work on status/reconcile). */
export async function getLiveKitBroadcastRoomPresence(
  roomId: string,
  broadcasterUserId: string,
  options?: { primaryMediaPublisherIdentity?: string | null }
): Promise<LiveKitBroadcastPresence | null> {
  const client = getLiveKitRoomServiceClient()
  if (!client) return null

  const primaryId = options?.primaryMediaPublisherIdentity?.trim() || null

  try {
    const participants = await client.listParticipants(
      liveKitBroadcastRoomName(roomId)
    )
    const hostConnected = participants.some(
      (p) => p.identity === broadcasterUserId
    )
    const primaryParticipant = primaryId
      ? participants.find((p) => p.identity === primaryId)
      : undefined
    const primaryMediaPublisherConnected = primaryId
      ? primaryPublisherHasPublishableVideo(primaryParticipant)
      : false
    const broadcasterConnected = hostConnected || primaryMediaPublisherConnected
    const viewerCount = participants.filter((p) => {
      if (p.identity === broadcasterUserId) return false
      if (primaryId && p.identity === primaryId) return false
      return true
    }).length
    return {
      hostConnected,
      primaryMediaPublisherConnected,
      broadcasterConnected,
      viewerCount,
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    if (/not found|does not exist|404/i.test(message)) {
      return {
        hostConnected: false,
        primaryMediaPublisherConnected: false,
        broadcasterConnected: false,
        viewerCount: 0,
      }
    }
    console.warn("[livekit/broadcast] presence check failed", message)
    return null
  }
}

export async function isBroadcasterConnectedInBroadcastRoom(
  roomId: string,
  broadcasterUserId: string,
  primaryMediaPublisherIdentity?: string | null
): Promise<boolean> {
  const presence = await getLiveKitBroadcastRoomPresence(
    roomId,
    broadcasterUserId,
    { primaryMediaPublisherIdentity: primaryMediaPublisherIdentity ?? undefined }
  )
  return presence?.broadcasterConnected ?? false
}

export async function deleteLiveKitBroadcastRoom(roomId: string): Promise<void> {
  const client = getLiveKitRoomServiceClient()
  if (!client) return
  try {
    await client.deleteRoom(liveKitBroadcastRoomName(roomId))
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    if (/not found|does not exist|404/i.test(message)) {
      return
    }
    console.warn("[livekit/broadcast] delete room failed", message)
  }
}

export async function countLiveKitGeneralVoicePresence(
  roomId: string
): Promise<{ connectedCount: number; speakingCount: number } | null> {
  const client = getLiveKitRoomServiceClient()
  if (!client) return null

  try {
    const participants = await client.listParticipants(liveKitRoomName(roomId))
    return summarizeGeneralVoicePresence(participants)
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    if (/not found|does not exist|404/i.test(message)) {
      return { connectedCount: 0, speakingCount: 0 }
    }
    console.warn("[livekit/voice] presence lookup failed", message)
    return null
  }
}

export async function countLiveKitBroadcastViewers(
  roomId: string,
  broadcasterUserId: string,
  primaryMediaPublisherIdentity?: string | null
): Promise<number | null> {
  const presence = await getLiveKitBroadcastRoomPresence(roomId, broadcasterUserId, {
    primaryMediaPublisherIdentity: primaryMediaPublisherIdentity ?? undefined,
  })
  return presence?.viewerCount ?? null
}
