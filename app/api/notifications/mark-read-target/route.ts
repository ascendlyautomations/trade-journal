import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { markNotificationsReadForTarget } from "@/lib/notificationReadSync"
import { invalidateAppIconBadgeCache } from "@/lib/server/push/badgeService"

type Body = {
  conversationId?: string
  roomId?: string
  roomSlug?: string
  postId?: string
  tradeId?: string
  profilePostId?: string
  achievementPostId?: string
  reelId?: string
  followRequestSenderId?: string
  markConversationRead?: boolean
  markRoomRead?: boolean
}

/**
 * Mark Activity notifications (and optionally conversation/room unread) as read.
 * Used by web views and iOS notification actions.
 */
export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  let body: Body
  try {
    body = (await req.json()) as Body
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 })
  }

  let updated = 0

  if (body.conversationId?.trim()) {
    const conversationId = body.conversationId.trim()

    updated += await markNotificationsReadForTarget(
      user.id,
      { kind: "conversation", conversationId },
      supabaseServiceRole
    )
    invalidateAppIconBadgeCache(user.id)

    if (body.markConversationRead !== false) {
      const now = new Date().toISOString()
      const { error } = await supabaseServiceRole
        .from("conversation_member_preferences")
        .upsert(
          {
            user_id: user.id,
            conversation_id: conversationId,
            last_read_at: now,
          },
          { onConflict: "user_id,conversation_id" }
        )
      if (error) {
        console.error("[mark-read-target] conversation prefs", error)
      }
    }
  }

  if (body.roomId?.trim() || body.roomSlug?.trim()) {
    let roomId = body.roomId?.trim() || ""
    if (!roomId && body.roomSlug?.trim()) {
      const { data: room } = await supabaseServiceRole
        .from("rooms")
        .select("id")
        .eq("slug", body.roomSlug.trim())
        .maybeSingle()
      roomId = room?.id ? String(room.id) : ""
    }

    updated += await markNotificationsReadForTarget(
      user.id,
      {
        kind: "room",
        roomId,
        roomSlug: body.roomSlug ?? null,
      },
      supabaseServiceRole
    )
    invalidateAppIconBadgeCache(user.id)

    if (body.markRoomRead !== false && roomId) {
      const { error } = await supabaseServiceRole
        .from("room_members")
        .update({ last_read_at: new Date().toISOString() })
        .eq("room_id", roomId)
        .eq("user_id", user.id)
        .is("left_at", null)
      if (error) {
        console.error("[mark-read-target] room members", error)
      }
    }
  }

  if (
    body.postId ||
    body.tradeId ||
    body.profilePostId ||
    body.achievementPostId ||
    body.reelId
  ) {
    updated += await markNotificationsReadForTarget(
      user.id,
      {
        kind: "feed",
        postId: body.postId,
        tradeId: body.tradeId,
        profilePostId: body.profilePostId,
        achievementPostId: body.achievementPostId,
        reelId: body.reelId,
      },
      supabaseServiceRole
    )
    invalidateAppIconBadgeCache(user.id)
  }

  if (body.followRequestSenderId?.trim()) {
    updated += await markNotificationsReadForTarget(
      user.id,
      {
        kind: "follow_request",
        senderId: body.followRequestSenderId.trim(),
      },
      supabaseServiceRole
    )
    invalidateAppIconBadgeCache(user.id)
  }

  return Response.json({ ok: true, updated })
}
