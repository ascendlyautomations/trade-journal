import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import { WebhookReceiver } from "livekit-server-sdk"
import { readLiveKitServerConfig } from "./config.ts"
import { parseLiveKitBroadcastRoomName } from "./liveKitRoomName.ts"
import {
  endTradeRoomBroadcastIfActive,
  getActiveTradeRoomBroadcast,
} from "./tradeRoomBroadcastSession.ts"
import { getLiveKitRoomServiceClient } from "./liveKitRoomService.ts"

export async function handleLiveKitWebhookForBroadcast(
  admin: SupabaseClient<Database>,
  rawBody: string,
  authorizationHeader: string | null
): Promise<{ ok: true; handled: boolean } | { ok: false; status: number; error: string }> {
  const config = readLiveKitServerConfig()
  if (!config) {
    return { ok: false, status: 503, error: "LiveKit is not configured." }
  }

  const receiver = new WebhookReceiver(config.apiKey, config.apiSecret)
  let event: Awaited<ReturnType<WebhookReceiver["receive"]>>
  try {
    event = await receiver.receive(rawBody, authorizationHeader ?? undefined)
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    console.warn("[livekit/webhook] verify failed", message)
    return { ok: false, status: 401, error: "Invalid LiveKit webhook signature." }
  }

  const roomName = event.room?.name?.trim()
  if (!roomName) {
    return { ok: true, handled: false }
  }

  const parsed = parseLiveKitBroadcastRoomName(roomName)
  if (!parsed) {
    return { ok: true, handled: false }
  }

  const active = await getActiveTradeRoomBroadcast(admin, parsed.roomId)
  if (!active) {
    return { ok: true, handled: false }
  }

  const identity = event.participant?.identity?.trim()
  if (identity !== active.broadcasterUserId) {
    return { ok: true, handled: false }
  }

  const eventName = event.event
  const trackSource = String(event.track?.source ?? "")
  const trackType = String(event.track?.type ?? "")
  const shouldEnd =
    eventName === "participant_left" ||
    (eventName === "track_unpublished" &&
      (trackSource.includes("SCREEN_SHARE") || trackType.includes("SCREEN")))

  if (!shouldEnd) {
    return { ok: true, handled: false }
  }

  await endTradeRoomBroadcastIfActive(admin, {
    roomId: parsed.roomId,
    sessionId: active.id,
    broadcasterUserId: active.broadcasterUserId,
    reason: eventName === "participant_left" ? "livekit_left" : "livekit_track_end",
  })

  const client = getLiveKitRoomServiceClient()
  if (client) {
    try {
      await client.removeParticipant(roomName, active.broadcasterUserId)
    } catch {
      // already gone
    }
  }

  return { ok: true, handled: true }
}
