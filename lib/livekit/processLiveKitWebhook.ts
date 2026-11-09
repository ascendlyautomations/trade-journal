import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import { WebhookReceiver } from "livekit-server-sdk"
import { readLiveKitServerConfig } from "./config.ts"
import { parseLiveKitBroadcastRoomName } from "./liveKitRoomName.ts"
import {
  getActiveTradeRoomBroadcast,
  updateBroadcastIngressSnapshot,
} from "./tradeRoomBroadcastSession.ts"
import {
  isObsIngressPublisherIdentity,
} from "./tradeRoomBroadcastObsIdentity.ts"
import {
  clearBroadcasterDisconnectCheck,
  isStaleLiveKitBroadcastWebhookEvent,
  scheduleBroadcasterDisconnectCheck,
} from "./tradeRoomBroadcastDisconnectCheck.ts"
import { ingressStatusLabel } from "./liveKitIngressService.ts"

export type LiveKitBroadcastWebhookResult =
  | {
      ok: true
      handled: boolean
      deferredDisconnectCheck?: { roomId: string; sessionId: string }
    }
  | { ok: false; status: number; error: string }

export async function handleLiveKitWebhookForBroadcast(
  admin: SupabaseClient<Database>,
  rawBody: string,
  authorizationHeader: string | null
): Promise<LiveKitBroadcastWebhookResult> {
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

  const active = await getActiveTradeRoomBroadcast(admin, parsed.roomId, {
    activeScope: "any",
  })
  if (!active) {
    return { ok: true, handled: false }
  }

  if (
    isStaleLiveKitBroadcastWebhookEvent(
      event.createdAt,
      active.startedAt
    )
  ) {
    return { ok: true, handled: false }
  }

  const eventName = event.event

  if (eventName === "ingress_started" || eventName === "ingress_ended") {
    const ingressId = event.ingressInfo?.ingressId?.trim() || ""
    const expectedIngress = active.livekitIngressId?.trim() || ""
    if (!ingressId || !expectedIngress || ingressId !== expectedIngress) {
      return { ok: true, handled: false }
    }

    if (eventName === "ingress_started") {
      const label = ingressStatusLabel(event.ingressInfo)
      await updateBroadcastIngressSnapshot(admin, {
        roomId: parsed.roomId,
        sessionId: active.id,
        ingressStatusLabel: label,
      })
      return { ok: true, handled: true }
    }

    await scheduleBroadcasterDisconnectCheck(admin, {
      roomId: parsed.roomId,
      sessionId: active.id,
      reason: "livekit_ingress_ended",
    })
    return {
      ok: true,
      handled: true,
      deferredDisconnectCheck: {
        roomId: parsed.roomId,
        sessionId: active.id,
      },
    }
  }

  const identity = event.participant?.identity?.trim()
  const primaryId = active.primaryMediaPublisherIdentity?.trim() || ""
  const isHost = identity === active.broadcasterUserId
  const isPrimaryProgram =
    primaryId !== "" && identity === primaryId && isObsIngressPublisherIdentity(primaryId)
  if (!isHost && !isPrimaryProgram) {
    return { ok: true, handled: false }
  }

  if (eventName === "participant_joined") {
    await clearBroadcasterDisconnectCheck(admin, {
      roomId: parsed.roomId,
      sessionId: active.id,
    })
    return { ok: true, handled: true }
  }

  const trackSource = String(event.track?.source ?? "")
  const trackType = String(event.track?.type ?? "")
  const shouldScheduleLeaveGrace =
    eventName === "participant_left" ||
    (isHost &&
      eventName === "track_unpublished" &&
      (trackSource.includes("SCREEN_SHARE") || trackType.includes("SCREEN")))

  if (!shouldScheduleLeaveGrace) {
    return { ok: true, handled: false }
  }

  const reason =
    eventName === "participant_left" ? "livekit_left" : "livekit_track_end"

  await scheduleBroadcasterDisconnectCheck(admin, {
    roomId: parsed.roomId,
    sessionId: active.id,
    reason,
  })

  return {
    ok: true,
    handled: true,
    deferredDisconnectCheck: {
      roomId: parsed.roomId,
      sessionId: active.id,
    },
  }
}
