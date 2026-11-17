import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { buildTradeRoomHref } from "@/lib/notificationsDisplay"
import { buildTradeRoomBroadcastLiveNotifyContent } from "@/lib/livekit/tradeRoomBroadcastLiveNotifyContent.ts"
import { dispatchPushNotification } from "@/lib/server/push/pushDispatcher"
import { filterRecipientsByRoomMessagePreference } from "@/lib/serverNotificationPreferences"

const PUSH_BATCH_SIZE = 40

/**
 * Notifies eligible Trade Room members when a host goes live (push only — same
 * pattern as ordinary room message fanout).
 */
export async function notifyTradeRoomMembersBroadcastLive(params: {
  roomId: string
  broadcasterUserId: string
  broadcastSessionId: string
}): Promise<{ pushed: number; skipped: boolean }> {
  const roomId = params.roomId.trim()
  const broadcasterUserId = params.broadcasterUserId.trim()
  const broadcastSessionId = params.broadcastSessionId.trim()
  if (!roomId || !broadcasterUserId || !broadcastSessionId) {
    return { pushed: 0, skipped: true }
  }

  const { data: roomRow, error: roomErr } = await supabaseServiceRole
    .from("rooms")
    .select("id, slug, name")
    .eq("id", roomId)
    .maybeSingle()

  if (roomErr) {
    console.error("[livekit/broadcast/live-notify] room lookup failed", roomErr)
    return { pushed: 0, skipped: true }
  }
  if (!roomRow?.slug) {
    return { pushed: 0, skipped: true }
  }

  const { data: sessionRow, error: sessionErr } = await supabaseServiceRole
    .from("room_live_broadcasts")
    .select("stream_title")
    .eq("id", broadcastSessionId)
    .eq("room_id", roomId)
    .is("ended_at", null)
    .maybeSingle()

  if (sessionErr) {
    console.error(
      "[livekit/broadcast/live-notify] session lookup failed",
      sessionErr
    )
    return { pushed: 0, skipped: true }
  }

  const streamTitle = sessionRow?.stream_title?.trim() ?? ""
  if (!streamTitle) {
    console.warn("[livekit/broadcast/live-notify] missing stream_title", {
      broadcastSessionId,
    })
    return { pushed: 0, skipped: true }
  }

  const { data: members, error: membersErr } = await supabaseServiceRole
    .from("room_members")
    .select("user_id")
    .eq("room_id", roomId)
    .eq("notification_enabled", true)
    .is("left_at", null)
    .neq("user_id", broadcasterUserId)

  if (membersErr) {
    console.error(
      "[livekit/broadcast/live-notify] members lookup failed",
      membersErr
    )
    return { pushed: 0, skipped: true }
  }

  let recipientIds = (members ?? [])
    .map((row) => String(row.user_id))
    .filter((id) => id.length > 0)

  recipientIds = await filterRecipientsByRoomMessagePreference(recipientIds)
  if (recipientIds.length === 0) {
    return { pushed: 0, skipped: false }
  }

  const content = buildTradeRoomBroadcastLiveNotifyContent({
    roomId,
    roomSlug: roomRow.slug,
    roomName: roomRow.name ?? "Trade Room",
    broadcastSessionId,
    streamTitle,
  })

  const contentJson = JSON.stringify(content)

  for (let i = 0; i < recipientIds.length; i += PUSH_BATCH_SIZE) {
    const batch = recipientIds.slice(i, i + PUSH_BATCH_SIZE)
    await Promise.all(
      batch.map((recipientUserId) =>
        dispatchPushNotification({
          recipientUserId,
          type: "room_live",
          sender_id: broadcasterUserId,
          room_id: roomId,
          content: contentJson,
          preferenceKey: "room_live_streams_enabled",
        })
      )
    )
  }

  console.info("[livekit/broadcast/live-notify] fanout complete", {
    roomId,
    broadcastSessionId,
    recipients: recipientIds.length,
    href: buildTradeRoomHref(roomRow.slug, { live: true }),
  })

  return { pushed: recipientIds.length, skipped: false }
}
