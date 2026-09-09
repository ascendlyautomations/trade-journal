import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { emitActivityNotification } from "@/lib/server/notifications/emit"
import { invalidateAppIconBadgeCache } from "@/lib/server/push/badgeService"
import { buildTradeRoomHref } from "@/lib/notificationsDisplay"
import {
  buildTradeRoomJoinAcceptedContent,
  buildTradeRoomJoinDeclinedContent,
  buildTradeRoomJoinRequestContent,
  buildTradeRoomJoinRequestHref,
} from "@/lib/tradeRoomJoinRequestContent"

type RoomRow = {
  id: string
  name: string | null
  slug: string | null
  owner_user_id: string | null
  room_kind: string | null
}

async function loadRoom(roomId: string): Promise<RoomRow | null> {
  const { data, error } = await supabaseServiceRole
    .from("rooms")
    .select("id, name, slug, owner_user_id, room_kind")
    .eq("id", roomId)
    .maybeSingle()
  if (error || !data) return null
  return data as RoomRow
}

async function loadRecipientIds(roomId: string): Promise<string[]> {
  const { data, error } = await supabaseServiceRole.rpc(
    "trade_room_join_request_recipient_ids",
    { p_room_id: roomId }
  )
  if (error) {
    console.error("[trade-room-join-request] recipient lookup failed", error)
    return []
  }
  const ids = (data ?? []) as string[]
  return Array.from(new Set(ids.map((id) => String(id).trim()).filter(Boolean)))
}

async function upsertJoinRequestNotification(params: {
  recipientUserId: string
  senderUserId: string
  roomId: string
  requestId: string
  roomSlug: string | null
  roomName: string | null
}): Promise<void> {
  const content = buildTradeRoomJoinRequestContent({
    joinRequestId: params.requestId,
    roomSlug: params.roomSlug,
    roomName: params.roomName,
    requestStatus: "pending",
    href: buildTradeRoomJoinRequestHref(params.requestId),
  })

  const { data: existing, error: lookupErr } = await supabaseServiceRole
    .from("notifications")
    .select("id")
    .eq("user_id", params.recipientUserId)
    .eq("sender_id", params.senderUserId)
    .eq("room_id", params.roomId)
    .eq("type", "trade_room_join_request")
    .maybeSingle()

  if (lookupErr) {
    console.error("[trade-room-join-request] lookup failed", lookupErr)
    return
  }

  if (existing?.id) {
    const { error: updateErr } = await supabaseServiceRole
      .from("notifications")
      .update({
        content,
        read: false,
        created_at: new Date().toISOString(),
      })
      .eq("id", existing.id)
    if (updateErr) {
      console.error("[trade-room-join-request] update failed", updateErr)
    } else {
      invalidateAppIconBadgeCache(params.recipientUserId)
    }
    return
  }

  await emitActivityNotification({
    row: {
      user_id: params.recipientUserId,
      sender_id: params.senderUserId,
      type: "trade_room_join_request",
      room_id: params.roomId,
      content,
    },
    push: {
      recipientUserId: params.recipientUserId,
      type: "trade_room_join_request",
      sender_id: params.senderUserId,
      room_id: params.roomId,
      content,
      prefsAlreadyChecked: true,
    },
    logLabel: "notifications/trade-room-join-request",
  })
}

export async function notifyTradeRoomJoinRequest(
  actorUserId: string,
  roomId: string,
  requestId: string
): Promise<{ ok: boolean; skipped?: boolean; error?: string; status?: number }> {
  const trimmedRoomId = roomId.trim()
  const trimmedRequestId = requestId.trim()
  if (!trimmedRoomId || !trimmedRequestId) {
    return { ok: false, error: "Invalid roomId or requestId", status: 400 }
  }

  const { data: requestRow, error: requestErr } = await supabaseServiceRole
    .from("room_join_requests")
    .select("id, room_id, user_id, status")
    .eq("id", trimmedRequestId)
    .maybeSingle()

  if (requestErr) {
    return { ok: false, error: requestErr.message, status: 500 }
  }
  if (!requestRow) {
    return { ok: false, error: "Join request not found", status: 404 }
  }
  if (String(requestRow.user_id) !== actorUserId) {
    return { ok: false, error: "Forbidden", status: 403 }
  }
  if (String(requestRow.room_id) !== trimmedRoomId) {
    return { ok: false, error: "Room mismatch", status: 400 }
  }
  if (requestRow.status !== "pending") {
    return { ok: true, skipped: true }
  }

  const room = await loadRoom(trimmedRoomId)
  if (!room) {
    return { ok: false, error: "Room not found", status: 404 }
  }

  const recipients = (await loadRecipientIds(trimmedRoomId)).filter(
    (id) => id !== actorUserId
  )
  if (recipients.length === 0) {
    return { ok: true, skipped: true }
  }

  await Promise.all(
    recipients.map((recipientUserId) =>
      upsertJoinRequestNotification({
        recipientUserId,
        senderUserId: actorUserId,
        roomId: trimmedRoomId,
        requestId: trimmedRequestId,
        roomSlug: room.slug,
        roomName: room.name,
      })
    )
  )

  return { ok: true }
}

export async function syncTradeRoomJoinRequestNotifications(
  requestId: string,
  status: "approved" | "rejected"
): Promise<void> {
  const { error } = await supabaseServiceRole.rpc(
    "sync_trade_room_join_request_notifications",
    {
      p_request_id: requestId,
      p_status: status,
    }
  )
  if (error) {
    console.error("[trade-room-join-request] sync notifications failed", error)
  }
}

export async function notifyTradeRoomJoinAccepted(params: {
  requesterUserId: string
  resolverUserId: string
  roomId: string
}): Promise<void> {
  const room = await loadRoom(params.roomId)
  if (!room) return

  const href = room.slug ? buildTradeRoomHref(room.slug) : "/community"
  const content = buildTradeRoomJoinAcceptedContent({
    roomSlug: room.slug,
    roomName: room.name,
    href,
  })

  await emitActivityNotification({
    row: {
      user_id: params.requesterUserId,
      sender_id: params.resolverUserId,
      type: "trade_room_join_accepted",
      room_id: params.roomId,
      content,
    },
    push: {
      recipientUserId: params.requesterUserId,
      type: "trade_room_join_accepted",
      sender_id: params.resolverUserId,
      room_id: params.roomId,
      content,
      prefsAlreadyChecked: true,
    },
    logLabel: "notifications/trade-room-join-accepted",
  })
}

export async function notifyTradeRoomJoinDeclined(params: {
  requesterUserId: string
  resolverUserId: string
  roomId: string
}): Promise<void> {
  const room = await loadRoom(params.roomId)
  if (!room) return

  const content = buildTradeRoomJoinDeclinedContent({
    roomSlug: room.slug,
    roomName: room.name,
  })

  await emitActivityNotification({
    row: {
      user_id: params.requesterUserId,
      sender_id: params.resolverUserId,
      type: "trade_room_join_declined",
      room_id: params.roomId,
      content,
    },
    push: {
      recipientUserId: params.requesterUserId,
      type: "trade_room_join_declined",
      sender_id: params.resolverUserId,
      room_id: params.roomId,
      content,
      prefsAlreadyChecked: true,
    },
    logLabel: "notifications/trade-room-join-declined",
  })
}
